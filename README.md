# Deepracer-For-Dummies
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

#### Scripts

* training

	* start.sh
		* starts the whole environment using docker compose
		* it will also open a terminal window where you can monitor the log output from the sagemaker training directory
		* it will also automatically open vncviewer so you can watch the training happening in Gazebo
	* stop.sh
		* stops the whole environment
		* automatically finds and stops the training container which was started from the sagemaker container


* evaluation
	* work in progress

* log-analysis
	* startes a container running jupyter labs with the log analysis notebooks which were originally provided by AWS and then extended by  Tomasz Ptak
	* the logs from robomaker are automatically mounted in the container so you don't have to move any files around
