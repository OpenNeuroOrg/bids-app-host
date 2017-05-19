#!/bin/bash
set -eo pipefail

function pull_and_prune {
    DISK_USAGE=$(df -P . | awk -F\  'FNR==2{ print $5 }')
    # Always prune when disk usage is above 80%
    if [ ${DISK_USAGE%?} -ge 80 ]; then
        docker system prune --all --force
        docker pull "$1"
    else
        docker pull "$1" || { docker system prune --all --force && docker pull "$1"; }
    fi
}

if [ -z "$BIDS_CONTAINER" ]; then
    echo "Error: Missing env variable BIDS_CONTAINER." && exit 1
elif [ -z "$BIDS_DATASET_BUCKET" ] && [ -z "$DEBUG" ]; then
    echo "Error: Missing env variable BIDS_DATASET_BUCKET." && exit 1
elif [ -z "$BIDS_OUTPUT_BUCKET" ] && [ -z "$DEBUG" ]; then
    echo "Error: Missing env variable BIDS_OUTPUT_BUCKET." && exit 1
elif [ -z "$BIDS_SNAPSHOT_ID" ]; then
    echo "Error: Missing env variable BIDS_SNAPSHOT_ID." && exit 1
elif [ -z "$BIDS_ANALYSIS_ID" ]; then
    echo "Error: Missing env variable BIDS_ANALYSIS_ID." && exit 1
elif [ -z "$BIDS_ANALYSIS_LEVEL" ]; then
    echo "Error: Missing env variable BIDS_ANALYSIS_LEVEL." && exit 1
fi

AWS_CLI_CONTAINER=infrastructureascode/aws-cli:1.11.89
pull_and_prune "$AWS_CLI_CONTAINER"

# Create volumes for snapshot/output if they do not already exist
docker volume create --name "$BIDS_SNAPSHOT_ID"
docker volume create --name "$BIDS_ANALYSIS_ID"

# Sync those volumes
docker run -v "$BIDS_SNAPSHOT_ID":/snapshot $AWS_CLI_CONTAINER aws s3 sync s3://"$BIDS_DATASET_BUCKET"/"$BIDS_SNAPSHOT_ID" /snapshot
docker run -v "$BIDS_ANALYSIS_ID":/output $AWS_CLI_CONTAINER aws s3 sync s3://"$BIDS_OUTPUT_BUCKET"/"$BIDS_SNAPSHOT_ID"/"$BIDS_ANALYSIS_ID" /ouput

# On exit, copy the output
function sync_output {
    docker run -v "$BIDS_ANALYSIS_ID":/output $AWS_CLI_CONTAINER -- aws s3 sync /ouput s3://"$BIDS_OUTPUT_BUCKET"/"$BIDS_SNAPSHOT_ID"/"$BIDS_ANALYSIS_ID"
}
trap sync_output EXIT

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

ARGUMENTS_ARRAY=( "$BIDS_ARGUMENTS" )

# Pull once, if pull fails, try to prune, if the second pull fails this will exit early
pull_and_prune "$BIDS_CONTAINER"

docker run -i --rm \
   -v "$BIDS_SNAPSHOT_ID":/snapshot:ro \
   -v "$BIDS_ANALYSIS_ID":/output \
   "$BIDS_CONTAINER" \
   /snapshot /output "$BIDS_ANALYSIS_LEVEL" \
   ${ARGUMENTS_ARRAY[@]}
