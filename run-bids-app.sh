#!/bin/bash
# Start up the docker service
nohup sh -c dockerd-entrypoint.sh &

set -eo pipefail

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

# Disable s3fs for debugging since it relies on EC2 roles
if [ -z "$DEBUG" ]; then
mkdir -p /tmp/bids_dataset
mkdir -p /tmp/outputs

s3fs -o "use_cache=/tmp/bids_dataset" -o "allow_other" -o "iam_role=auto" "$BIDS_DATASET_BUCKET" /bids_dataset
s3fs -o "use_cache=/tmp/outputs" -o "allow_other" -o "iam_role=auto" "$BIDS_OUTPUT_BUCKET" /outputs
fi

# Make sure we've given time for Docker to start
until docker ps; do
    sleep 1
done

ARGUMENTS_ARRAY=( "$BIDS_ARGUMENTS" )

docker run -i --rm \
   -v /bids_dataset/"$BIDS_SNAPSHOT_ID":/bids_dataset:ro \
   -v /outputs/"$BIDS_SNAPSHOT_ID"/"$BIDS_ANALYSIS_ID":/outputs \
   "$BIDS_CONTAINER" \
   /bids_dataset /outputs "$BIDS_ANALYSIS_LEVEL" \
   ${ARGUMENTS_ARRAY[@]}
