# DeepRacer-For-Dummies
a quick way to get up and running with local deepracer training environment


# Getting Started

#### Local Environment Setup

This section provides steps to setup a local environment in a dual-boot configuration and uses the Anaconda python distribution to manage package installation on the host.  It meets the Prerequisites defined below, before being able to run ./init.sh.

* This setup describes a local dual-boot environment with Windows 10 and Ubuntu 18.04.
* I chose the Anaconda Python distribution to install Nvidia Cuda and the cuDNN library.
* Note - Tensorflow and all other python requirements are taken care of in this repo's Dockerfile.

##### 1. Install Ubuntu 18.04

For a local dual-boot setup with WIndows 10, I found this guide simple to follow:

https://medium.com/bigdatarepublic/dual-boot-windows-and-linux-aa281c3c01f9

When it gets to the Disk Management part, to make space for your Ubuntu installation, I followed this guide and was only successful using the 2nd method (MiniTool Partition Wizard):

https://win10faq.com/shrink-partition-windows-10/?source=post_page---------------------------

##### 2. Install Docker.io

	sudo apt install docker.io

Additionally, make sure your user-id can run docker without sudo:
https://docs.docker.com/install/linux/linux-postinstall/

##### 3. Install nvidia-docker

The NVIDIA Container Toolkit allows users to build and run GPU accelerated Docker containers.  
Nvidia-docker essentially exposes the GPU to the containers to use:  https://github.com/NVIDIA/nvidia-docker

	distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
	
	curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -

	curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

	sudo apt-get update
	sudo apt-get install -y nvidia-container-toolkit  (note: nvidia-docker2 packages are deprecated)
	sudo systemctl restart docker

##### 4. Install the proper nvidia drivers

Check for driver version here according to your GPU(s):  https://www.nvidia.com/Download/index.aspx?lang=en-us

	sudo apt-get purge nvidia*
	sudo add-apt-repository ppa:graphics-drivers
	sudo apt-get update
	sudo apt-get install screen
	screen
	sudo apt install nvidia-driver-430 && sudo reboot 
Note: 430 is a driver version that is compatible with my GPU, according to that nvidia website

Verify the driver installation:
	
	nvidia-smi  

##### 5. Download the Anaconda python distribution

Grab the latest version here for Linux-x86_64: https://repo.anaconda.com/archive/

	sudo apt-get update -y && sudo apt-get upgrade -y
	cd /tmp/
	wget https://repo.anaconda.com/archive/<enter-the-desired-filename-from-the-Anaconda-repo>
	
Verify the integrity of the file by matching the md5 hash to the one on the Anaconda repo site for your file:  

	md5sum <enter-the-desired-filename-from-the-Anaconda-repo>

##### 6. Install Anaconda

	bash <enter-the-desired-filename-from-the-Anaconda-repo>
	"yes" for using the default directory location

Activate Anaconda:  
	
	source ~/.bashrc
	
Make sure conda works:

	conda list
	
##### 7. Install vnc viewer on your local machine

This doc is straight forward: https://www.techspot.com/downloads/5760-vnc-viewer.html

##### 8. Install libraries to access the GPU hardware:

	conda install cudnn==7.3.1
	conda install -c fragcolor cuda10.0

Verify installed.

	conda list

##### 9. Setup AWS CLI

	pip install -U awscli
	
Then Follow this: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html

##### 10. Run Init.sh from this repo (refer to the rest of this doc for script details) 

Note init.sh basically performs these steps so you don't have to do them manually:
1. Clones Chris's repo:  https://github.com/crr0004/deepracer.git
2. Does a mkdir -p ~/.sagemaker && cp config.yaml ~/.sagemaker
3. Sets the image name in rl_deepracer_coach_robomaker.py  to "crr0004/sagemaker-rl-tensorflow:nvidia”
4. Also sets the instance_type in rl_deepracer_coach_robomaker.py to “local_gpu”
5. Copies the reward.py and model-metadata files into your Minio bucket

---
#### Prerequisites

* This project is specifically built to run on Ubuntu 18.04 with an **Nvidia GPU**. It is assumed you already have **CUDA/CUDNN** installed and configured.

* You also need to have **Docker** installed as well as the **Nvidia-Docker** runtime.

* You should have an AWS account with the **AWS cli** installed. The credentials should be located in your home directory (~/.aws/credentials)

* ensure you have **vncviewer** installed

#### Initialization

In a command prompt, simply run "./init.sh".
This will set everything up so you can run the deepracer local training environment.

To start or stop the local deepracer training, use the scripts found in the scripts directory.

Here is a brief overview of the available scripts

#### Hyperparameters

You can modify training hyperparameters from the file **rl_deepracer_coach_robomaker.py**.

#### Action Space & Reward Function

The action-space and reward function files are located in the **deepracer-for-dummies/docker/volumes/minio/bucket/custom_files** directory

#### Track Selection

The track selection is controled via an environment variable in the **.env** file located in the **deepracer-for-dummies/docker** directory

#### Scripts

* training

	* start.sh
		* starts the whole environment using docker compose
		* it will also open a terminal window where you can monitor the log output from the sagemaker training directory
		* it will also automatically open vncviewer so you can watch the training happening in Gazebo
	* stop.sh
		* stops the whole environment
		* automatically finds and stops the training container which was started from the sagemaker container
	* upload-snapshot.sh
		* uploads a specific snapshot to S3 in AWS. If no checkpoint is provided, it attempts to retrieve the latest snapshot


* evaluation
	* work in progress

* log-analysis
	* start.sh
		* starts a container with Nvidia-Docker running jupyter labs with the log analysis notebooks which were originally provided by AWS and then extended by  Tomasz Ptak
		* the logs from robomaker are automatically mounted in the container so you don't have to move any files around
		* in order to get to the container, look at the log output from when it starts. You need to grab the URL including the token query parameter and then paste it into the brower at **localhost:8888**.
	* stop.sh
		* stops the log-analysis container
