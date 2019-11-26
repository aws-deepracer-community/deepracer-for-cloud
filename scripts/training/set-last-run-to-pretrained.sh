#!/usr/bin/env bash
Folder=rl-deepracer-sagemaker
if [ -d ../../docker/volumes/minio/bucket/rl-deepracer-sagemaker ];
then
	echo "Folder $Folder  exist."
	rm -rf ../../docker/volumes/minio/bucket/rl-deepracer-pretrained
	mv ../../docker/volumes/minio/bucket/rl-deepracer-sagemaker ../../docker/volumes/minio/bucket/rl-deepracer-pretrained
	echo "Done."

else
	echo "Folder $Folder does not exist" 
fi
