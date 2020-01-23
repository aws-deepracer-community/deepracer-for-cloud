# DeepRacer-For-Cloud
Provides a quick and easy way to get up and running with a DeepRacer training environment in Azure or AWS, using either the Azure [N-Series Virtual Machines](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-gpu) or [AWS EC2 Accelerating Computing instances](https://aws.amazon.com/ec2/instance-types/?nc1=h_ls#Accelerated_Computing).

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
* Robomaker, RL Coach and Log Analysis Docker images are now available as downloads in [Docker Hub](https://hub.docker.com/search?q=larsll%2Fdeepracer&type=image), which reduces the time to build a new VM.



## Installation

A step by step [installation guide](https://github.com/larsll/deepracer-for-azure/wiki/Install-DeepRacer-in-Azure) is available.

TODO: Create an end-to-end installation script.

## Usage

Before every session run `source activate.sh` to ensure that the environment variables are set correctly. This also creates a set of aliases/commands that makes it easier to operate the setup.

Ensure that the configuration files are uploaded into the bucket `dr-upload-local-custom-files`. Start a training with `dr-start-local-training`.
