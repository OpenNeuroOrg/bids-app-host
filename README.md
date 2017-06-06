This container is meant to encapsulate [BIDS App containers](http://bids-apps.neuroimaging.io/) for execution with AWS roles and S3 inputs/outputs.

## Required environment variables/configuration:
* BIDS_ANALYSIS_ID: A unique key for a combination of dataset and parameters
* BIDS_CONTAINER: path:tag for BIDS app container
* BIDS_DATASET_BUCKET: S3 Bucket containing BIDS directories
* BIDS_OUTPUT_BUCKET: Writable S3 Bucket for output
* BIDS_SNAPSHOT_ID: The key to reference which BIDS directory
* BIDS_ANALYSIS_LEVEL: Select for participant, group, etc
* BIDS_ARGUMENTS: Optionally any additional parameters required

## Optional environment variables

These are mostly useful for debugging.

* DISABLE_PRUNE: Prevents the container from removing images/volumes
* AWS_ACCESS_KEY_ID: Optionally use these credentials with S3
* AWS_SECRET_ACCESS_KEY: Optionally use these credentials with S3

If no S3 credentials are provided, the EC2 instance role is used.
