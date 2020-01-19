# set evaluation specific environment variables
export ROBOMAKER_COMMAND="./run.sh build evaluation.launch"
export METRICS_S3_OBJECT_KEY=metrics/eval_metrics.json
export NUMBER_OF_TRIALS=5

docker-compose -f ../../docker/docker-compose.yml up -d


echo 'waiting for containers to start up...'

#sleep for 20 seconds to allow the containers to start
sleep 15

if ! [ -x "$(command -v gnome-terminal)" ]; 
then
  docker logs -f robomaker
else	
  echo 'attempting to pull up robomaker logs...'
  gnome-terminal -x sh -c "!!; docker logs -f docker logs -f robomaker"
fi
