export ROBOMAKER_RUN_TYPE=evaluation
export METRICS_S3_OBJECT_KEY=custom_files/eval_metrics.json

docker-compose -f ../../docker/docker-compose.yml up -d


gnome-terminal -x sh -c "!!; docker logs -f $(docker ps | awk ' /sagemaker/ { print $1 }')"

gnome-terminal -x sh -c "!!; vncviewer localhost:8080"