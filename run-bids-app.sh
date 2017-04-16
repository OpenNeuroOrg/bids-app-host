#!/bin/bash
# Environment variables:
# BIDS_CONTAINER
# BIDS_DIR_BUCKET
# OUTPUT_DIR_BUCKET
# PARTICIPANT_FLAG
# PARTICIPANT_LABEL

riofs -o "allow_other" $BIDS_DIR_BUCKET /bids_dataset
riofs -o "allow_other" $OUTPUT_DIR_BUCKET /outputs

# Make sure we've given time for Docker to start
sleep 5

if [ -z "$PARTICIPANT_FLAG" ]; then
    docker run -i --rm \
	   -v /bids_dataset:/bids_dataset:ro \
	   -v /outputs:/outputs \
	   $BIDS_CONTAINER \
	   /bids_dataset /outputs participant --participant_label $PARTICIPANT_LABEL
else
    docker run -i --rm \
	   -v /bids_dataset:/bids_dataset:ro \
	   -v /outputs:/outputs \
	   $BIDS_CONTAINER \
	   /bids_dataset /outputs
fi
