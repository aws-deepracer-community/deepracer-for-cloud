# Introduction

Provides a quick and easy way to get up and running with a DeepRacer training environment in AWS or Azure, using either the Azure [N-Series Virtual Machines](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-gpu) or [AWS EC2 Accelerated Computing instances](https://aws.amazon.com/ec2/instance-types/?nc1=h_ls#Accelerated_Computing), or locally on your own desktop or server.

DeepRacer-For-Cloud (DRfC) started as an extension of the work done by Alex (https://github.com/alexschultz/deepracer-for-dummies), which is again a wrapper around the amazing work done by Chris (https://github.com/crr0004/deepracer). With the introduction of the second generation Deepracer Console the repository has been split up. This repository contains the scripts needed to *run* the training, but depends on Docker Hub to provide pre-built docker images. All the under-the-hood building capabilities have been moved to my [Deepracer Build](https://gitbub.com/larsll/deepracer-build) repository.

Main differences to the work done by Alex is:
* Runtime S3 storage is setup to fit the connected cloud platform:
	* Azure: Local 'virtual' S3 instance (minio) is now using an Azure Storage Account / Blob Storage as a back-end. This allows for access between sesssions using e.g. Storage Explorer (https://azure.microsoft.com/en-us/features/storage-explorer/).
	* AWS: Directly connects to a real S3 bucket.
	* Local: Local 'virtual' S3 instance (minio) storing files locally on the server.
* Robomaker and Log Analysis containers are extended with required drivers to enable Tensorflow to use the GPU. Containers are all pre-compiled and available from Docker Hub.
* Configuration has been reorganized :
	* `custom_files/hyperparameters.json` stores the runtime hyperparameters, which logically belongs together with the model_metadata.json and rewards.py files.
	* `system.env` contains system-wide constants (expected to be configured only at setup)
	* `run.env` contains user session configuration (pretraining, track etc.) as well as information about where to upload your model (S3 bucket and prefix).

# Main Features

DRfC supports a wide set of features to ensure that you can focus on creating the best model:
* User-friendly
	* Based on the continously updated community [Robomaker](https://github.com/aws-deepracer-community/deepracer-simapp) and [Sagemaker](https://github.com/aws-deepracer-community/deepracer-sagemaker-container) containers, supporting a wide range of CPU and GPU setups.
	* Wide set of scripts (`dr-*`) enables effortless training.
	* Detection of your AWS DeepRacer Console models; allows upload of a locally trained model to any of them.
* Modes
	* Time Trial
	* Object Avoidance
	* Head-to-Bot
* Training
	* Multiple Robomaker instances per Sagemaker (N:1) to improve training progress.
	* Multiple training sessions in parallel - each being (N:1) if hardware supports it - to test out things in parallel.
	* Connect multiple nodes together (Swarm-mode only) to combine the powers of multiple computers/instances.
* Evaluation
	* Evaluate independently from training.
	* Save evaluation run to MP4 file in S3.
* Logging
	* Training metrics and trace files are stored to S3.
	* Optional integration with AWS CloudWatch.
	* Optional exposure of Robomaker internal log-files.
* Technology
	* Supports both Docker Swarm (used for connecting multiple nodes together) and Docker Compose (used to support OpenGL)

# Documentation

* [Initial Installation](installation)
* [Reference](reference)
* [GPU Accelerated OpenGL for Robomaker](opengl)

# Support

* For general support it is suggested to join the [AWS DeepRacing Community](https://deepracing.io/). The Community Slack has a channel #dr-drfc-setup where the community provides active support.
* Create a GitHub issue if you find an actual code issue, or where updates to documentation would be required.
