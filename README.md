# DeepRacer-For-Cloud
Provides a quick and easy way to get up and running with a DeepRacer training environment in Azure or AWS, using either the Azure [N-Series Virtual Machines](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-gpu) or [AWS EC2 Accelerated Computing instances](https://aws.amazon.com/ec2/instance-types/?nc1=h_ls#Accelerated_Computing).

This repo is an extension of the work done by Alex (https://github.com/alexschultz/deepracer-for-dummies), which is again a wrapper around the amazing work done by Chris (https://github.com/crr0004/deepracer)

Please refer to Chris' repo to understand more about what's going on under the covers.

Main differences to the work done by Alex is:
* Runtime S3 storage is setup to fit the connected cloud platform:
	* Azure: Local 'virtual' S3 instance (minio) is now using an Azure Storage Account / Blob Storage as a back-end. This allows for access between sesssions using e.g. Storage Explorer (https://azure.microsoft.com/en-us/features/storage-explorer/).
	* AWS: Directly connects to a real S3 bucket.
* Robomaker and Log Analysis containers are extended with required drivers to enable Tensorflow to use the GPU. Containers are all pre-compiled and available from Docker Hub.
* Configuration has been reorganized :
	* `custom_files/hyperparameters.json` stores the runtime hyperparameters, which logically belongs together with the model_metadata.json and rewards.py files.
	* `current-run.env` contains user session configuration (pretraining, track etc.) as well as information about where to upload your model (S3 bucket and prefix).
	* `docker/.env` remains the home for more static configuration. This is not expected to change between sessions.
* Runtime storage: Uses `/mnt` to store robomaker files (checkpoints, logs); depending on setup these will normally be deleted between runs, but Azure and AWS provides 200+ GB free storage which is very suitable for this purpuse. Archiving of logs and additional checkpoint files required if desired.
	* Azure: Uses the normal temporary drive which is mounted on /mnt by default.
	* AWS: Preparation scripts mounts the ephemeral drive on /mnt
* Robomaker, RL Coach and Log Analysis Docker images are now available as downloads in [Docker Hub](https://hub.docker.com/search?q=larsll%2Fdeepracer&type=image), which reduces the time to build a new VM. Log analysis is not downloaded by default to reduce required disk space.

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

A step by step [installation guide](https://github.com/larsll/deepracer-for-cloud/wiki/Install-DeepRacer-in-Azure) for manual installation in Azure is available.

The package comes with preparation and setup scripts that would allow a turn-key setup for a fresh virtual machine.

	git clone https://github.com/larsll/deepracer-for-cloud.git
	cd deepracer-for-cloud && ./bin/prepare.sh
	
This will prepare the VM by partitioning additional drives as well as installing all prerequisites. After a reboot it will continuee to run `./bin/init.sh` setting up the full repository and downloading the core Docker images. Depending on your environment this may take up to 30 minutes. The scripts will create a file `DONE` once completed.

The installation script will adapt `.profile` to ensure that all settings are applied on login.

For local install it is recommended *not* to run the `bin/prepare.sh` script; it might do more changes than what you want. Rather ensure that all prerequisites are set up and run `bin/init.sh` directly.

*TODO: Document how to configure via cloud-init.*
*TODO: Create a local setup prepare script*

## Environment Setup

The environment is set via the `CLOUD` parameter in `current-run.env`; it can be `Azure`, `AWS` or `Local`. It is case-insensitive. Depending on the value the virtual or native S3 instance will be configured accordingly.

Note: If in the `bin/prepare.sh` script then the working directory `/mnt/deepracer` will be provided based on the temporary storage partitions made available. If you want to provision the working directory in a different fashion then just ensure that a volume is mounted on `/mnt` or `/mnt/deepracer` with sufficient storage.

### AWS

In AWS it is possible to set up authentication to S3 in two ways: Integrated sign-on using [IAM Roles](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html) or using access keys.

#### IAM Roles

To use IAM Roles:
* An empty S3 bucket in the same region as the EC2 instance.
* An IAM Role that has permissions to access both the *new* S3 bucket as well as the DeepRacer bucket.
* An EC2 instance with the IAM Role assigned.
* Configure `current-run.env` as follows:
  * `LOCAL_S3_PROFILE=default`
  * `LOCAL_S3_BUCKET=<bucketname>`
  * `UPLOAD_S3_PROFILE=default`
  * `UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.


#### Manual setup
For access with IAM user:
* An empty S3 bucket in the same region as the EC2 instance.
* A real AWS IAM user set up with access keys:
  * User should have permissions to access the *new* bucket as well as the dedicated DeepRacer S3 bucket.
  * Use `aws configure` to configure this into the default profile. 
* Configure `current-run.env` as follows:
  * `LOCAL_S3_PROFILE=default`
  * `LOCAL_S3_BUCKET=<bucketname>`
  * `UPLOAD_S3_PROFILE=default`
  * `UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.

### Azure

In Azure mode the script-set requires the following:
* A storage account with a blob container set up with access keys:
	* Use `aws configure --profile <myprofile>` to configure this into a specific profile. 
    	* Access Key ID is the Storage Account name. 
    	* Secret Access Key is the Access Key for the Storage Account.
  	* The blob container is equivalent to the S3 bucket.
* A real AWS IAM user configured with `aws configure` to enable upload of models into AWS DeepRacer.
* Configure `current-run.env` as follows:
  * `LOCAL_S3_PROFILE=<myprofile>`
  * `LOCAL_S3_BUCKET=<blobcontainer-name>`
  * `UPLOAD_S3_PROFILE=default`
  * `UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.

As Azure does not natively support S3 a [minio](https://min.io/product/overview) proxy is set up on port 9000 to allow the containers to communicate and store models.

If you want to use awscli (`aws`) to manually move files then use `aws $LOCAL_PROFILE_ENDPOINT_URL s3 ...`, as this will set both `--profile` and `--endpoint-url` parameters to match your configuration.

### Local

Local mode runs a minio server that hosts the data in the `/mnt/deepracer` partition. It is otherwise command-compatible with the Azure setup; as the data is accessible via Minio and not via native S3.

### Environment Variables
The scripts assume that a file `current-run.env` is populated with the required values.

| Variable | Description |
|----------|-------------|
| `CLOUD` | Can be `Azure` or `AWS`; determines how the storage will be configured.|
| `WORLD_NAME` | Defines the track to be used.| 
| `NUMBER_OF_TRIALS` | Defines the number of trials in an evaluation session.| 
| `CHANGE_START_POSITION` | Determines if the racer shall round-robin the starting position during training sessions. (Recommended to be `True` for initial training.)| 
| `LOCAL_S3_PROFILE` | Name of AWS profile with credentials to be used. Stored in `~/.aws/credentials` unless AWS IAM Roles are used.|
| `LOCAL_S3_BUCKET` | Name of S3 bucket which will be used during the session.|
| `LOCAL_S3_MODEL_PREFIX` | Prefix of model within S3 bucket.|
| `LOCAL_S3_CUSTOM_FILES_PREFIX` | Prefix of configuration files within S3 bucket.|
| `LOCAL_S3_LOGS_PREFIX` | Prefix of log files within S3 bucket. |
| `LOCAL_S3_PRETRAINED` | Determines if training or evaluation shall be based on the model created in a previous session, held in `s3://{LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`, accessible by credentials held in profile `{LOCAL_S3_PROFILE}`.| 
| `LOCAL_S3_PRETRAINED_PREFIX` | Prefix of pretrained model within S3 bucket.|
| `LOGS_ACCESS_KEY` | Username for local S3 log proxy (minio container).|
| `LOGS_ACCESS_SECRET` | Password for local S3 log proxy (minio container).|
| `UPLOAD_S3_PROFILE` | AWS Cli profile to be used that holds the 'real' S3 credentials needed to upload a model into AWS DeepRacer.|
| `UPLOAD_S3_BUCKET` | Name of the AWS DeepRacer bucket where models will be uploaded. (Typically starts with `aws-deepracer-`.)|
| `UPLOAD_S3_PREFIX` | Prefix of the target location. (Typically starts with `DeepRacer-SageMaker-RoboMaker-comm-`|
| `UPLOAD_MODEL_NAME` | Display name of model, not currently used; `dr-set-upload-model` sets it for readability purposes.|


## Usage

Before every session run `dr-update` to ensure that the environment variables are set correctly. This also creates a set of aliases/commands that makes it easier to operate the setup. If `dr-update` is not found, try `source activate.sh` to get aliases defined.

Ensure that the configuration files are uploaded into the bucket `dr-upload-custom-files`. Start a training with `dr-start-training`.

### Commands

| Command | Description |
|---------|-------------|
| `dr-update` | Loads in all scripts and environment variables again.| 
| `dr-update-env` | Loads in all environment variables from `current-run.env`.|
| `dr-upload-custom-files` | Uploads changed configuration files from `custom_files/` into `s3://{LOCAL_S3_BUCKET}/custom_files`.|
| `dr-download-custom-files` | Downloads changed configuration files from `s3://{LOCAL_S3_BUCKET}/custom_files` into `custom_files/`.|
| `dr-upload-logs` | Uploads changed Robomaker log files from `/mnt/deepracer/robo/checkpoint/log` into `s3://{LOCAL_S3_BUCKET}/${LOCAL_S3_LOGS_PREFIX}`.|
| `dr-start-training` | Starts a training session in the local VM based on current configuration.|
| `dr-increment-training` | Updates configuration, setting the current model prefix to pretrained, and incrementing a serial.|
| `dr-stop-training` | Stops the current local training session. Uploads log files.|
| `dr-start-evaluation` | Starts a evaluation session in the local VM based on current configuration.|
| `dr-stop-evaluation` | Stops the current local evaluation session. Uploads log files.|
| `dr-start-loganalysis` | Starts a Jupyter log-analysis container, available on port 8888.|
| `dr-start-loganalysis` | Stops the Jupyter log-analysis container.|
| `dr-logs-sagemaker` | Displays the logs from the running Sagemaker container.|
| `dr-logs-robomaker` | Displays the logs from the running Robomaker container.|
| `dr-logs-start-proxy` | Starts a local Minio S3 instance on port 9001 to expose files in `/mnt/deepracer/robo/checkpoint/log`. Useful if doing log analysis outside of VM.
| `dr-logs-stop-proxy` | Stops the local Minio S3 instance on port 9001. |
| `dr-list-aws-models` | Lists the models that are currently stored in your AWS DeepRacer S3 bucket. |
| `dr-set-upload-model` | Updates the `current-run.env` with the prefix and name of your selected model. |
| `dr-upload-model` | Uploads the model defined in `LOCAL_S3_MODEL_PREFIX` to the AWS DeepRacer S3 prefix defined in `UPLOAD_S3_PREFIX` |