#!/bin/bash
if [ "$(awk '{print $1}' /proc/$PPID/comm)" == "supervisord" ]; then
    # Always kill supervisord when this script exits
    trap 'kill -s SIGTERM $PPID' EXIT
fi

set -eo pipefail

if [ -z "$BIDS_CONTAINER" ]; then
    echo "Error: Missing env variable BIDS_CONTAINER." && exit 1
elif [ -z "$BIDS_DATASET_BUCKET" ]; then
    echo "Error: Missing env variable BIDS_DATASET_BUCKET." && exit 1
elif [ -z "$BIDS_OUTPUT_BUCKET" ]; then
    echo "Error: Missing env variable BIDS_OUTPUT_BUCKET." && exit 1
elif [ -z "$BIDS_SNAPSHOT_ID" ]; then
    echo "Error: Missing env variable BIDS_SNAPSHOT_ID." && exit 1
elif [ -z "$BIDS_ANALYSIS_ID" ]; then
    echo "Error: Missing env variable BIDS_ANALYSIS_ID." && exit 1
elif [ -z "$BIDS_ANALYSIS_LEVEL" ]; then
    echo "Error: Missing env variable BIDS_ANALYSIS_LEVEL." && exit 1
fi

mkdir -p /tmp/bids_dataset
mkdir -p /tmp/outputs

s3fs -o "use_cache=/tmp/bids_dataset" -o "allow_other" -o "iam_role=auto" "$BIDS_DIR_BUCKET" /bids_dataset
s3fs -o "use_cache=/tmp/outputs" -o "allow_other" -o "iam_role=auto" "$OUTPUT_DIR_BUCKET" /outputs

# Make sure we've given time for Docker to start
until [ -S /var/run/docker.sock ]; do
    sleep 0.1
done

docker run -i --rm \
   -v /bids_dataset/"$BIDS_SNAPSHOT_ID":/bids_dataset:ro \
   -v /outputs/"$BIDS_SNAPSHOT_ID"/"$BIDS_ANALYSIS_ID":/outputs \
   "$BIDS_CONTAINER" \
   /bids_dataset /outputs "$BIDS_ANALYSIS_LEVEL" \
   "$BIDS_ARGUMENTS"
