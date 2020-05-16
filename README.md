# DeepRacer-For-Cloud
Provides a quick and easy way to get up and running with a DeepRacer training environment in Azure or AWS, using either the Azure [N-Series Virtual Machines](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-gpu) or [AWS EC2 Accelerated Computing instances](https://aws.amazon.com/ec2/instance-types/?nc1=h_ls#Accelerated_Computing).

This repo started as an extension of the work done by Alex (https://github.com/alexschultz/deepracer-for-dummies), which is again a wrapper around the amazing work done by Chris (https://github.com/crr0004/deepracer). With the introduction of the second generation Deepracer Console the repository has been split up. This repository contains the scripts needed to *run* the training, but depends on Docker Hub to provide pre-built docker images. All the under-the-hood building capabilities have been moved to my [Deepracer Build](https://gitbub.com/larsll/deepracer-build) repository.

Main differences to the work done by Alex is:
* Runtime S3 storage is setup to fit the connected cloud platform:
	* Azure: Local 'virtual' S3 instance (minio) is now using an Azure Storage Account / Blob Storage as a back-end. This allows for access between sesssions using e.g. Storage Explorer (https://azure.microsoft.com/en-us/features/storage-explorer/).
	* AWS: Directly connects to a real S3 bucket.
* Robomaker and Log Analysis containers are extended with required drivers to enable Tensorflow to use the GPU. Containers are all pre-compiled and available from Docker Hub.
* Configuration has been reorganized :
	* `custom_files/hyperparameters.json` stores the runtime hyperparameters, which logically belongs together with the model_metadata.json and rewards.py files.
	* `system.env` contains system-wide constants (expected to be configured only at setup)
	* `run.env` contains user session configuration (pretraining, track etc.) as well as information about where to upload your model (S3 bucket and prefix).
	* `docker/.env` remains the home for more static configuration. This is not expected to change between sessions.

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

### Environment Variables
The scripts assume that two files `systen.env` containing constant configuration values and  `run.env` with run specific values is populated with the required values. Which values go into which file is not really important.

| Variable | Description |
|----------|-------------|
| `DR_CLOUD` | Can be `azure`, `aws` or `local`; determines how the storage will be configured.|
| `DR_WORLD_NAME` | Defines the track to be used.| 
| `DR_NUMBER_OF_TRIALS` | Defines the number of trials in an evaluation session.| 
| `DR_CHANGE_START_POSITION` | Determines if the racer shall round-robin the starting position during training sessions. (Recommended to be `True` for initial training.)| 
| `DR_LOCAL_S3_PROFILE` | Name of AWS profile with credentials to be used. Stored in `~/.aws/credentials` unless AWS IAM Roles are used.|
| `DR_LOCAL_S3_BUCKET` | Name of S3 bucket which will be used during the session.|
| `DR_LOCAL_S3_MODEL_PREFIX` | Prefix of model within S3 bucket.|
| `DR_LOCAL_S3_CUSTOM_FILES_PREFIX` | Prefix of configuration files within S3 bucket.|
| `DR_LOCAL_S3_PRETRAINED` | Determines if training or evaluation shall be based on the model created in a previous session, held in `s3://{DR_LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`, accessible by credentials held in profile `{DR_LOCAL_S3_PROFILE}`.| 
| `DR_LOCAL_S3_PRETRAINED_PREFIX` | Prefix of pretrained model within S3 bucket.|
| `DR_LOCAL_S3_PARAMS_FILE` | YAML file path used to configure Robomaker relative to `s3://{DR_LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`.| 
| `DR_UPLOAD_S3_PROFILE` | AWS Cli profile to be used that holds the 'real' S3 credentials needed to upload a model into AWS DeepRacer.|
| `DR_UPLOAD_S3_BUCKET` | Name of the AWS DeepRacer bucket where models will be uploaded. (Typically starts with `aws-deepracer-`.)|
| `DR_UPLOAD_S3_PREFIX` | Prefix of the target location. (Typically starts with `DeepRacer-SageMaker-RoboMaker-comm-`|
| `DR_UPLOAD_MODEL_NAME` | Display name of model, not currently used; `dr-set-upload-model` sets it for readability purposes.|
| `DR_CAR_COLOR` | Color of car | 
| `DR_CAR_NAME` | Display name of car; shows in Deepracer Console when uploading. |
| `DR_AWS_APP_REGION` | (AWS only) Region for other AWS resources (e.g. Kinesis) |
| `DR_KINESIS_STREAM_NAME` | Kinesis stream name | 
| `DR_KINESIS_STREAM_ENABLE` | Enable or disable Kinesis Stream | 
| `DR_GUI_ENABLE` | Enable or disable the Gazebo GUI in Robomaker | 
| `DR_GPU_AVAILABLE` | Is GPU enabled? | 
| `DR_DOCKER_IMAGE_TYPE` | `cpu` or `gpu`; docker images will be used based on this | 

## Usage

Before every session run `dr-update` to ensure that the environment variables are set correctly. This also creates a set of aliases/commands that makes it easier to operate the setup. If `dr-update` is not found, try `source activate.sh` to get aliases defined.

Ensure that the configuration files are uploaded into the bucket `dr-upload-custom-files`. Start a training with `dr-start-training`.

### Commands

| Command | Description |
|---------|-------------|
| `dr-update` | Loads in all scripts and environment variables again.| 
| `dr-update-env` | Loads in all environment variables from `system.env` and `run.env`.|
| `dr-upload-custom-files` | Uploads changed configuration files from `custom_files/` into `s3://{DR_LOCAL_S3_BUCKET}/custom_files`.|
| `dr-download-custom-files` | Downloads changed configuration files from `s3://{DR_LOCAL_S3_BUCKET}/custom_files` into `custom_files/`.|
| `dr-start-training` | Starts a training session in the local VM based on current configuration.|
| `dr-increment-training` | Updates configuration, setting the current model prefix to pretrained, and incrementing a serial.|
| `dr-stop-training` | Stops the current local training session. Uploads log files.|
| `dr-start-evaluation` | Starts a evaluation session in the local VM based on current configuration.|
| `dr-stop-evaluation` | Stops the current local evaluation session. Uploads log files.|
| `dr-start-loganalysis` | Starts a Jupyter log-analysis container, available on port 8888.|
| `dr-start-loganalysis` | Stops the Jupyter log-analysis container.|
| `dr-logs-sagemaker` | Displays the logs from the running Sagemaker container.|
| `dr-logs-robomaker` | Displays the logs from the running Robomaker container.|
| `dr-list-aws-models` | Lists the models that are currently stored in your AWS DeepRacer S3 bucket. |
| `dr-set-upload-model` | Updates the `run.env` with the prefix and name of your selected model. |
| `dr-upload-model` | Uploads the model defined in `DR_LOCAL_S3_MODEL_PREFIX` to the AWS DeepRacer S3 prefix defined in `DR_UPLOAD_S3_PREFIX` |
