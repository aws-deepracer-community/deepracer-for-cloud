#!/usr/bin/env bash

usage(){
	echo "Usage: $0 [-t topic] [-w width] [-h height] [-q quality] -b [browser-command]"
  echo "       -w        Width of individual stream."
  echo "       -h        Heigth of individual stream."
  echo "       -q        Quality of the stream image."
  echo "       -t        Topic to follow - default /racecar/deepracer/kvs_stream"
  echo "       -b        Browser command (default: firefox --new-tab)"
	exit 1
}

trap ctrl_c INT

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}

# Stream definition
TOPIC="/racecar/deepracer/kvs_stream"
WIDTH=480
HEIGHT=360
QUALITY=75
BROWSER="firefox --new-tab"

while getopts ":w:h:q:t:b:" opt; do
case $opt in
w) WIDTH="$OPTARG"
;;
h) HEIGHT="$OPTARG"
;;
q) QUALITY="$OPTARG"
;;
t) TOPIC="$OPTARG"
;;
b) BROWSER="$OPTARG"
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done

export DR_VIEWER_HTML=$DR_DIR/tmp/streams-$DR_RUN_ID.html
export DR_NGINX_CONF=$DR_DIR/tmp/streams-$DR_RUN_ID.conf

cat << EOF > $DR_NGINX_CONF
server {
  listen 80;
  location / {
    root   /usr/share/nginx/html;
    index  index.html index.htm;
  }
EOF
echo "<html><head><title>DR-$DR_RUN_ID - $DR_LOCAL_S3_MODEL_PREFIX - $TOPIC</title></head><body><h1>DR-$DR_RUN_ID - $DR_LOCAL_S3_MODEL_PREFIX - $TOPIC</h1>" > $DR_VIEWER_HTML

ROBOMAKER_CONTAINERS=$(docker ps --format "{{.ID}}" --filter name=deepracer-$DR_RUN_ID --filter "ancestor=awsdeepracercommunity/deepracer-robomaker:$DR_ROBOMAKER_IMAGE")
if [ -z "$ROBOMAKER_CONTAINERS" ]; then
    echo "No running robomakers. Exiting."
    exit
fi

for c in $ROBOMAKER_CONTAINERS; do
    C_URL="/$c/stream?topic=${TOPIC}&quality=${QUALITY}&width=${WIDTH}&height=${HEIGHT}"
    C_IMG="<img src=\"${C_URL}\"></img>"
    echo $C_IMG >> $DR_VIEWER_HTML
    echo "  location /$c { proxy_pass http://$c:8080; rewrite /$c/(.*) /\$1 break; }" >> $DR_NGINX_CONF
done

echo "</body></html>" >> $DR_VIEWER_HTML
echo "}" >> $DR_NGINX_CONF

# Check if we will use Docker Swarm or Docker Compose
STACK_NAME="deepracer-$DR_RUN_ID-viewer"
COMPOSE_FILES=$DR_DIR/docker/docker-compose-webviewer.yml

if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  docker stack deploy -c $COMPOSE_FILES $STACK_NAME
else
  docker-compose -f $COMPOSE_FILES -p $STACK_NAME --log-level ERROR up -d 
fi

# Starting browser if using local X and having display defined.
if [[ -n "${DISPLAY}" && "${DR_HOST_X,,}" == "true" ]]; then
  echo "Starting browser '$BROWSER'."
  $BROWSER "http://127.0.01:8100" &
fi

