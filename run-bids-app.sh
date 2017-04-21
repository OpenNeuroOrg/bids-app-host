#!/bin/bash
if [ "$(awk '{print $1}' /proc/$PPID/comm)" == "supervisord" ]; then
    # Always kill supervisord when this script exits
    trap 'kill -s SIGTERM $PPID' EXIT
fi

set -eo pipefail

if [ -z "$BIDS_CONTAINER" ]; then
    echo "Error: Missing env variable BIDS_CONTAINER." && exit 1
elif [ -z "$BIDS_DIR_BUCKET" ]; then
    echo "Error: Missing env variable BIDS_DIR_BUCKET." && exit 1
elif [ -z "$OUTPUT_DIR_BUCKET" ]; then
    echo "Error: Missing env variable OUTPUT_DIR_BUCKET." && exit 1
elif [ -z "$BIDS_SNAPSHOT_ID" ]; then
    echo "Error: Missing env variable OUTPUT_DIR_BUCKET." && exit 1
fi

mkdir -p /tmp/bids_dataset
mkdir -p /tmp/outputs

s3fs -o "use_cache=/tmp/bids_dataset" -o "allow_other" -o "iam_role=auto" $BIDS_DIR_BUCKET /bids_dataset
s3fs -o "use_cache=/tmp/outputs" -o "allow_other" -o "iam_role=auto" $OUTPUT_DIR_BUCKET /outputs

# Make sure we've given time for Docker to start
until [ -S /var/run/docker.sock ]; do
    sleep 0.1
done

if [ -z "$PARTICIPANT_FLAG" ]; then
    docker run -i --rm \
	   -v /bids_dataset/$BIDS_SNAPSHOT_ID:/bids_dataset:ro \
	   -v /outputs/$BIDS_SNAPSHOT_ID/$ANALYSIS_ID:/outputs \
	   $BIDS_CONTAINER \
	   /bids_dataset /outputs group
else
    docker run -i --rm \
	   -v /bids_dataset/$SNAPSHOT_ID:/bids_dataset:ro \
	   -v /outputs/$SNAPSHOT_ID/$ANALYSIS_ID:/outputs \
	   $BIDS_CONTAINER \
	   /bids_dataset /outputs participant --participant_label $PARTICIPANT_LABEL
fi
