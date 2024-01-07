#!/usr/bin/env bash

usage(){
	echo "Usage: $0 [-t topic] [-w width] [-h height] [-q quality] -b [browser-command] -p [port]"
  echo "       -w        Width of individual stream."
  echo "       -h        Heigth of individual stream."
  echo "       -q        Quality of the stream image."
  echo "       -t        Topic to follow - default /racecar/deepracer/kvs_stream"
  echo "       -b        Browser command (default: firefox --new-tab)"
  echo "       -p        The port to use "
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
PORT=$DR_WEBVIEWER_PORT

while getopts ":w:h:q:t:b:p:" opt; do
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
p) PORT="$OPTARG"
;;
\?) echo "Invalid option -$OPTARG" >&2
usage
;;
esac
done

DR_WEBVIEWER_PORT=$PORT

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


if [[ "${DR_DOCKER_STYLE,,}" != "swarm" ]]; then
  ROBOMAKER_CONTAINERS=$(docker ps --format "{{.ID}} {{.Names}}" --filter name="deepracer-${DR_RUN_ID}" | grep robomaker | cut -f1 -d\ )
else
  ROBOMAKER_SERVICE_REPLICAS=$(docker service ps deepracer-${DR_RUN_ID}_robomaker | awk '/robomaker/ { print $1 }')
  for c in $ROBOMAKER_SERVICE_REPLICAS; do
    ROBOMAKER_CONTAINER_IP=$(docker inspect $c | jq -r '.[].NetworksAttachments[] | select (.Network.Spec.Name == "sagemaker-local") | .Addresses[0] ' | cut -f1 -d/)
    ROBOMAKER_CONTAINERS="${ROBOMAKER_CONTAINERS} ${ROBOMAKER_CONTAINER_IP}"
  done
fi

if [ -z "$ROBOMAKER_CONTAINERS" ]; then
    echo "No running robomakers. Exiting."
    exit
fi

# Expose the diamensions to the HTML template
export QUALITY
export WIDTH
export HEIGHT
# Create .js array of robomakers to pass to the HTML template 
export ROBOMAKER_CONTAINERS_HTML="" 
for c in $ROBOMAKER_CONTAINERS; do
    ROBOMAKER_CONTAINERS_HTML+="'$c',"
done
SCRIPT_PATH="${BASH_SOURCE:-$0}"
ABS_SCRIPT_PATH="$(realpath "${SCRIPT_PATH}")"
ABS_DIRECTORY="$(dirname "${ABS_SCRIPT_PATH}")"
INDEX_HTML_TEMPLATE="${ABS_DIRECTORY}/index.template.html"
# Replace all variables in HTML template and create the viewer html file
envsubst < "${INDEX_HTML_TEMPLATE}" > $DR_VIEWER_HTML

# Add proxy paths in the NGINX file
for c in $ROBOMAKER_CONTAINERS; do
    echo "  location /$c { proxy_pass http://$c:8080; rewrite /$c/(.*) /\$1 break; }" >> $DR_NGINX_CONF
done
echo "}" >> $DR_NGINX_CONF

# Check if we will use Docker Swarm or Docker Compose
STACK_NAME="deepracer-$DR_RUN_ID-viewer"
COMPOSE_FILES=$DR_DIR/docker/docker-compose-webviewer.yml

if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]];
then
  COMPOSE_FILES="$COMPOSE_FILES -c $DR_DIR/docker/docker-compose-webviewer-swarm.yml"
  docker stack deploy -c $COMPOSE_FILES $STACK_NAME
else
  docker compose -f $COMPOSE_FILES -p $STACK_NAME --log-level ERROR up -d 
fi

# Starting browser if using local X and having display defined.
if [[ -n "${DISPLAY}" && "${DR_HOST_X,,}" == "true" ]]; then
  echo "Starting browser '$BROWSER'."
  if [ "${DR_DOCKER_STYLE,,}" == "swarm" ];
  then
    sleep 5
  fi
  $BROWSER "http://127.0.01:8100" &
fi

CURRENT_CONTAINER_HASH=$(docker ps | grep dr_viewer | head -c 12)

IP_ADDRESSES="$( hostname -I)";
echo "The viewer will avaliable on the following hosts after initialization:"
for ip in $IP_ADDRESSES;
do
    echo "http://${ip}:${PORT}"
done