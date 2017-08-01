#!/bin/bash
set -eo pipefail -x

# Minimum supported version is 1.24
# This script is written based on the 1.29 reference but tested against
# 1.24 and 1.29
DOCKER_API_VERSION=1.29

function docker_api_query {
    curl -s --unix-socket /var/run/docker.sock http:/$DOCKER_API_VERSION/$1
}

function docker_cleanup {
    if [ -z "DISABLE_PRUNE" ]; then
        # This is more aggressive than the default 3 hour cleanup of the ECS agent
        if [ $(docker_api_query version | jq -r '.ApiVersion') == '1.24' ]; then
            docker rmi $(docker images -f dangling=true)
            docker volume rm $(docker volume ls -f dangling=true -q)
        else
            docker system prune --all --force
        fi
    fi
}

function pull_and_prune {
    IMAGE_SPACE_AVAILABLE=$(docker_api_query info | jq -r '.DriverStatus[] | select(.[0] | match("Data Space Available")) | .[1]')
    VOLUME_SPACE_USED=$(df -P /var/run/docker.sock | awk -F\  'FNR==2{ print $5 }')
    echo "Host image storage available: $IMAGE_SPACE_AVAILABLE"
    echo "Host volume storage used: $VOLUME_SPACE_USED"
    # Check if there's at least 10 GB of image storage and 20% of volume storage free
    if [[ $IMAGE_SPACE_AVAILABLE == *GB ]] && [ $(printf "%.0f\n" "${IMAGE_SPACE_AVAILABLE% GB*}") -ge 10 ] && [ ${VOLUME_SPACE_USED%?} -le 80 ]; then
        # Retry the pull once if it still fails here
        docker pull "$1" || { docker_cleanup && docker pull "$1"; }
    else
        # If there wasn't enough disk space, prune and then pull
        docker_cleanup
        docker pull "$1"
    fi
}

if [ -z "$BIDS_CONTAINER" ]; then
    echo "Error: Missing env variable BIDS_CONTAINER." && exit 1
elif [ -z "$BIDS_DATASET_BUCKET" ] && [ -z "$DEBUG" ]; then
    echo "Error: Missing env variable BIDS_DATASET_BUCKET." && exit 1
elif [ -z "$BIDS_OUTPUT_BUCKET" ] && [ -z "$DEBUG" ]; then
    echo "Error: Missing env variable BIDS_OUTPUT_BUCKET." && exit 1
elif [ -z "$BIDS_INPUT_BUCKET" ] && [ -z "$DEBUG" ]; then
    echo "Error: Missing env variable BIDS_INPUT_BUCKET." && exit 1
elif [ -z "$BIDS_SNAPSHOT_ID" ]; then
    echo "Error: Missing env variable BIDS_SNAPSHOT_ID." && exit 1
elif [ -z "$BIDS_ANALYSIS_ID" ]; then
    echo "Error: Missing env variable BIDS_ANALYSIS_ID." && exit 1
elif [ -z "$BIDS_ANALYSIS_LEVEL" ]; then
    echo "Error: Missing env variable BIDS_ANALYSIS_LEVEL." && exit 1
fi

# Make sure the host docker instance is running
set +e # Disable -e because we expect docker ps to sometimes fail
ATTEMPTS=1
until docker ps &> /dev/null || [ $ATTEMPTS -eq 13 ]; do
    sleep 5
    ((ATTEMPTS++))
done
set -e

if [ $ATTEMPTS -eq 13 ]; then
    echo "Failed to find Docker service before timeout"
    exit 1
fi

AWS_CLI_CONTAINER=infrastructureascode/aws-cli:1.11.89
pull_and_prune "$AWS_CLI_CONTAINER"
# Pull once, if pull fails, try to prune
# if the second pull fails this will exit early
pull_and_prune "$BIDS_CONTAINER"

# On exit, copy the output
function sync_output {
    set +e
    docker run --rm -v "$AWS_BATCH_JOB_ID":/output $AWS_CLI_CONTAINER aws s3 sync --only-show-errors /output/data s3://"$BIDS_OUTPUT_BUCKET"/"$BIDS_SNAPSHOT_ID"/"$BIDS_ANALYSIS_ID"
    DOCKER_EC=$?
    if (( $DOCKER_EC == 2 )); then
        echo "Warning: aws s3 sync output returned status code 2"
        echo "Some files may not have been copied"
    else
        if (( $DOCKER_EC != 0 )); then
            # Pass any unhandled exit codes back to Batch
            exit $?
        fi
    fi
    # Unlock these volumes
    docker rm -f "$AWS_BATCH_JOB_ID"-lock || echo "No lock found for ${AWS_BATCH_JOB_ID}"
    set -e
}
trap sync_output EXIT

# Create volumes for snapshot/output if they do not already exist
echo "Creating snapshot volume:"
docker volume create --name "$BIDS_SNAPSHOT_ID"
echo "Creating output volume:"
docker volume create --name "$AWS_BATCH_JOB_ID"

# Check for file input hash "array" string
if [ "$INPUT_HASH_LIST" ]; then
    echo "Input file hash array found"
    # Convert hash list into a bash array
    INPUT_BASH_ARRAY=(`echo ${INPUT_HASH_LIST}`)
    # Concatenate all the hashes into one string to combine with input bucket to make a unique volume name
    HASH_STRING=""
    INCLUDE_STRING=""
    for hash in "${INPUT_BASH_ARRAY[@]}"
    do
        HASH_STRING+="$hash"
        INCLUDE_STRING+="--include \"*${hash}*\""
    done
    # Create input volume
    echo "Creating input volume:"
    docker volume create --name "${BIDS_INPUT_BUCKET}_${HASH_STRING}"
    # Input command to copy input files from s3
    INPUT_COMMAND="aws s3 cp --only-show-errors s3://${BIDS_INPUT_BUCKET}/ /input/data/ --recursive --exclude '*' ${INCLUDE_STRING}"
    echo "$INPUT_COMMAND"
fi

# Prevent a race condition where another container deletes these volumes
# after the syncs but before the main task starts
# Timeout after ten minutes to prevent infinite jobs
if [ "$INPUT_COMMAND" ]; then
    docker run --rm -d --name "$AWS_BATCH_JOB_ID"-lock -v "$BIDS_SNAPSHOT_ID":/snapshot -v "$AWS_BATCH_JOB_ID":/output -v "$BIDS_INPUT_BUCKET_$HASH_STRING":/input $AWS_CLI_CONTAINER sh -c 'sleep 600'
else
    docker run --rm -d --name "$AWS_BATCH_JOB_ID"-lock -v "$BIDS_SNAPSHOT_ID":/snapshot -v "$AWS_BATCH_JOB_ID":/output $AWS_CLI_CONTAINER sh -c 'sleep 600'
fi
# Sync those volumes
SNAPSHOT_COMMAND="aws s3 sync --only-show-errors s3://${BIDS_DATASET_BUCKET}/${BIDS_SNAPSHOT_ID} /snapshot/data"
OUTPUT_COMMAND="aws s3 sync --only-show-errors s3://${BIDS_OUTPUT_BUCKET}/${BIDS_SNAPSHOT_ID}/${BIDS_ANALYSIS_ID} /output/data"
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    docker run --rm -v "$BIDS_SNAPSHOT_ID":/snapshot $AWS_CLI_CONTAINER flock /snapshot/lock $SNAPSHOT_COMMAND
    docker run --rm -v "$AWS_BATCH_JOB_ID":/output $AWS_CLI_CONTAINER flock /output/lock $OUTPUT_COMMAND
    if [ "$INPUT_COMMAND" ]; then
        docker run --rm -v "${BIDS_INPUT_BUCKET}_${HASH_STRING}":/input $AWS_CLI_CONTAINER flock /input/lock $INPUT_COMMAND
    fi
else
    docker run --rm -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -v "$BIDS_SNAPSHOT_ID":/snapshot $AWS_CLI_CONTAINER flock /snapshot/lock $SNAPSHOT_COMMAND
    docker run --rm -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -v "$AWS_BATCH_JOB_ID":/output $AWS_CLI_CONTAINER flock /output/lock $OUTPUT_COMMAND
    if [ "$INPUT_COMMAND" ]; thenx
        docker run --rm -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -v "${BIDS_INPUT_BUCKET}_${HASH_STRING}":/input $AWS_CLI_CONTAINER flock /input/lock $INPUT_COMMAND
    fi
fi

ARGUMENTS_ARRAY=( "$BIDS_ARGUMENTS" )

if [ "$INPUT_COMMAND" ]; then
    COMMAND_TO_RUN="docker run -it --rm \
           -v \"$BIDS_SNAPSHOT_ID\":/snapshot:ro \
           -v \"$AWS_BATCH_JOB_ID\":/output \
           -v \"${BIDS_INPUT_BUCKET}_${HASH_STRING}\":/input:ro \
           \"$BIDS_CONTAINER\" \
           /snapshot/data /output/data \"$BIDS_ANALYSIS_LEVEL\" \
           ${ARGUMENTS_ARRAY[@]}"
else
    COMMAND_TO_RUN="docker run -it --rm \
           -v \"$BIDS_SNAPSHOT_ID\":/snapshot:ro \
           -v \"$AWS_BATCH_JOB_ID\":/output \
           \"$BIDS_CONTAINER\" \
           /snapshot/data /output/data \"$BIDS_ANALYSIS_LEVEL\" \
           ${ARGUMENTS_ARRAY[@]}"
fi

mapfile BIDS_APP_COMMAND <<EOF
    $COMMAND_TO_RUN
EOF

# Wrap with script so we have a PTY available regardless of parent shell
script -f -e -q -c "$BIDS_APP_COMMAND" /dev/null
