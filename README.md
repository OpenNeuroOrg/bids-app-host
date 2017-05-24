This container is meant to encapsulate [BIDS App containers](http://bids-apps.neuroimaging.io/) for execution with AWS roles and S3 inputs/outputs.

## Environment variables/configuration:
* BIDS_ANALYSIS_ID: A unique key for a combination of dataset and parameters
* BIDS_CONTAINER: path:tag for BIDS app container
* BIDS_DATASET_BUCKET: S3 Bucket containing BIDS directories
* BIDS_OUTPUT_BUCKET: Writable S3 Bucket for output
* BIDS_SNAPSHOT_ID: The key to reference which BIDS directory
* BIDS_ANALYSIS_LEVEL: Select for participant, group, etc
* BIDS_ARGUMENTS: Optionally any additional parameters required

## Limitations
Currently this only functions when running in an EC2 environment with IAM Roles assigned with access to the appropriate S3 buckets or with s3 credentials injected into the container.
