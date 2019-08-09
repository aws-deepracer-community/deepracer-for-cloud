# set evaluation specific environment variables
export ROBOMAKER_COMMAND="./run.sh build evaluation.launch"
export METRICS_S3_OBJECT_KEY=custom_files/eval_metrics.json
export NUMBER_OF_TRIALS=5

docker-compose -f ../../docker/docker-compose.yml up -d


echo 'waiting for containers to start up...'

#sleep for 20 seconds to allow the containers to start
sleep 15

echo 'attempting to pull up sagemaker logs...'
gnome-terminal -x sh -c "!!; docker logs -f $(docker ps | awk ' /sagemaker/ { print $1 }')"

echo 'attempting to open vnc viewer...'
gnome-terminal -x sh -c "!!; vncviewer localhost:8080"
