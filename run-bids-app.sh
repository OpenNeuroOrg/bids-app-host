#!/bin/bash
# Environment variables:
# BIDS_CONTAINER
# BIDS_DIR_BUCKET
# BIDS_SNAPSHOT_ID
# OUTPUT_DIR_BUCKET
# PARTICIPANT_FLAG
# PARTICIPANT_LABEL

if [ "$(ps -o comm= $PPID)" == "supervisord" ]; then
    # Always kill supervisord when this script exits
    trap 'kill -s SIGTERM $(supervisorctl pid)' EXIT
fi

set -eo pipefail

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY"]; then
    riofs -o "allow_other" $BIDS_DIR_BUCKET /bids_dataset
    riofs -o "allow_other" $OUTPUT_DIR_BUCKET /outputs
else
    echo "Error: AWS parameters not passed to this container"
    exit 1
fi

# Make sure we've given time for Docker to start
until [ -S /var/run/docker.sock ]; do
    sleep 0.1
done

if [ -z "$PARTICIPANT_FLAG" ]; then
    docker run -i --rm \
	   -v /bids_dataset/$BIDS_SNAPSHOT_ID:/bids_dataset:ro \
	   -v /outputs/$BIDS_SNAPSHOT_ID:/outputs \
	   $BIDS_CONTAINER \
	   /bids_dataset /outputs group
else
    docker run -i --rm \
	   -v /bids_dataset/$SNAPSHOT_ID:/bids_dataset:ro \
	   -v /outputs/$SNAPSHOT_ID:/outputs \
	   $BIDS_CONTAINER \
	   /bids_dataset /outputs participant --participant_label $PARTICIPANT_LABEL
fi
