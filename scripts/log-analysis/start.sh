#!/usr/bin/env bash

if docker ps --filter "name=deepracer-analysis" --format "{{.Names}}" | grep -q "^deepracer-analysis$"; then
  echo "Log-analysis is already running. Use dr-url-loganalysis to get the URL."
  exit 0
fi

echo "Starting log-analysis container (image: awsdeepracercommunity/deepracer-analysis:${DR_ANALYSIS_IMAGE})..."
docker run --rm -d -p "8888:8888" \
-v $DR_DIR/data/logs:/workspace/logs \
-v $DR_DIR/docker/volumes/.aws:/home/ubuntu/.aws \
-v $DR_DIR/data/analysis:/workspace/analysis \
-v $DR_DIR/data/minio:/workspace/minio \
--name deepracer-analysis \
--network sagemaker-local \
 awsdeepracercommunity/deepracer-analysis:$DR_ANALYSIS_IMAGE > /dev/null

echo "Waiting for Jupyter to start..."
for i in $(seq 1 30); do
  URL=$(docker logs deepracer-analysis 2>&1 | grep -oE 'http://127\.0\.0\.1:[0-9]+[^ ]*token=[a-f0-9]+' | tail -1)
  if [ -n "$URL" ]; then
    echo "Log-analysis is running. Open in browser:"
    echo "  ${URL/127.0.0.1/localhost}"
    exit 0
  fi
  sleep 1
done
echo "Log-analysis started. Use dr-url-loganalysis to get the URL once ready."