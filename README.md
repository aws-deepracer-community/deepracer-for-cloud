# DeepRacer-For-Dummies
a quick way to get up and running with local deepracer training environment


# Getting Started

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
