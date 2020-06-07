# Installing Deepracer-for-Cloud

## Requirements

Depending on your needs as well as specific needs of the cloud platform you can configure your VM to your liking.

**AWS**:
* EC2 instance of type G3, G4, P2 or P3 - recommendation is g4dn.2xlarge
	* Ubuntu 18.04
	* Minimum 30 GB, preferred 40 GB of OS disk.
	* Ephemeral Drive connected
	* Minimum 8 GB GPU-RAM
	* Recommended at least 6 VCPUs
* S3 bucket. Preferrably in same region as EC2 instance.

**Azure**:
* N-Series VM that comes with NVIDIA Graphics Adapter - recommendation is NC6_Standard
	* Ubuntu 18.04
	* Standard 30 GB OS drive is sufficient to get started. 
	* Recommended to add an additional 32 GB data disk if you want to use the Log Analysis container.
	* Minimum 8 GB GPU-RAM
	* Recommended at least 6 VCPUs
* Storage Account with one Blob container configured for Access Key authentication.
	
## Installation

The package comes with preparation and setup scripts that would allow a turn-key setup for a fresh virtual machine.

	git clone https://github.com/larsll/deepracer-for-cloud.git
	cd deepracer-for-cloud && ./bin/prepare.sh
	
This will prepare the VM by partitioning additional drives as well as installing all prerequisites. After a reboot it will continuee to run `./bin/init.sh` setting up the full repository and downloading the core Docker images. Depending on your environment this may take up to 30 minutes. The scripts will create a file `DONE` once completed.

The installation script will adapt `.profile` to ensure that all settings are applied on login. Otherwise run the activation with `source bin/activate.sh`.

For local install it is recommended *not* to run the `bin/prepare.sh` script; it might do more changes than what you want. Rather ensure that all prerequisites are set up and run `bin/init.sh` directly.

The Init Script takes a few parameters:

| Variable | Description |
|----------|-------------|
| `-c <cloud>` | Sets the cloud version to be configured, automatically updates the `DR_CLOUD` parameter in `system.env`. Options are `azure`, `aws` or `local`. Default is `local` |
| `-a <arch>` | Sets the architecture to be configured. Either `cpu` or `gpu`. Default is `gpu`. |

*TODO: Document how to configure via cloud-init.*

## Environment Setup

The environment is set via the `CLOUD` parameter in `system.env`; it can be `Azure`, `AWS` or `Local`. It is case-insensitive. Depending on the value the virtual or native S3 instance will be configured accordingly.

### AWS

In AWS it is possible to set up authentication to S3 in two ways: Integrated sign-on using [IAM Roles](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html) or using access keys.

#### IAM Roles

To use IAM Roles:
* An empty S3 bucket in the same region as the EC2 instance.
* An IAM Role that has permissions to:
  * Access both the *new* S3 bucket as well as the DeepRacer bucket.
  * AmazonVPCReadOnlyAccess
  * AmazonKinesisVideoStreamsFullAccess if you want to stream to Kinesis
* An EC2 instance with the IAM Role assigned.
* Configure `run.env` as follows:
  * `DR_LOCAL_S3_PROFILE=default`
  * `DR_LOCAL_S3_BUCKET=<bucketname>`
  * `DR_UPLOAD_S3_PROFILE=default`
  * `DR_UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update-env` for configuration to take effect.

#### Manual setup
For access with IAM user:
* An empty S3 bucket in the same region as the EC2 instance.
* A real AWS IAM user set up with access keys:
  * User should have permissions to access the *new* bucket as well as the dedicated DeepRacer S3 bucket.
  * Use `aws configure` to configure this into the default profile. 
* Configure `run.env` as follows:
  * `DR_LOCAL_S3_PROFILE=default`
  * `DR_LOCAL_S3_BUCKET=<bucketname>`
  * `DR_UPLOAD_S3_PROFILE=default`
  * `DR_UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.

### Azure

In Azure mode the script-set requires the following:
* A storage account with a blob container set up with access keys:
	* Use `aws configure --profile <myprofile>` to configure this into a specific profile. 
    	* Access Key ID is the Storage Account name. 
    	* Secret Access Key is the Access Key for the Storage Account.
  	* The blob container is equivalent to the S3 bucket.
* A real AWS IAM user configured with `aws configure` to enable upload of models into AWS DeepRacer.
* Configure `run.env` as follows:
  * `DR_LOCAL_S3_PROFILE=<myprofile>`
  * `DR_LOCAL_S3_BUCKET=<blobcontainer-name>`
  * `DR_UPLOAD_S3_PROFILE=default`
  * `DR_UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.

As Azure does not natively support S3 a [minio](https://min.io/product/overview) proxy is set up on port 9000 to allow the containers to communicate and store models.

If you want to use awscli (`aws`) to manually move files then use `aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 ...`, as this will set both `--profile` and `--endpoint-url` parameters to match your configuration.

### Local

Local mode runs a minio server that hosts the data in the `docker/volumes` directory. It is otherwise command-compatible with the Azure setup; as the data is accessible via Minio and not via native S3.

After having run init.sh do the following:
* Configure the Minio credentials with `aws configure --profile minio`. The default configuration will use the `minio` profile to configure MINIO. You can choose any username or password, but username needs to be at least length 3, and password at least length 8.
* Configure your normal AWS credentials with `aws configure` if this is not already in place on your system. This is required to use the model upload functionality.

## Basic Usage

Before every session run `dr-update` to ensure that the environment variables are set correctly. This also creates a set of aliases/commands that makes it easier to operate the setup. If `dr-update` is not found, try `source activate.sh` to get aliases defined.

Ensure that the configuration files are uploaded into the bucket `dr-upload-custom-files`. Start a training with `dr-start-training`.

