This container is meant to encapsulate [BIDS App containers](http://bids-apps.neuroimaging.io/) for execution with AWS roles and S3 inputs/outputs.

## Environment variables/configuration:
* ANALYSIS_ID: A unique key for related runs (fanout)
* BIDS_CONTAINER: path:tag for BIDS app container
* BIDS_DIR_BUCKET: S3 Bucket containing BIDS directories
* BIDS_SNAPSHOT_ID: The key to reference which BIDS directory
* OUTPUT_DIR_BUCKET: Writable S3 Bucket for output
* PARTICIPANT_FLAG: Toggle for participant instead of group modes
* PARTICIPANT_LABEL: Which participant(s) to process

## Limitations
Currently this only functions when running in an EC2 environment with IAM Roles assigned with access to the appropriate S3 buckets or with s3fs credentials injected into the container.
