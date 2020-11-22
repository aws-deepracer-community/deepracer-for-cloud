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
echo "<html><head><title>DR-$DR_RUN_ID - $DR_LOCAL_S3_MODEL_PREFIX - $TOPIC</title><link href=\"https://fonts.googleapis.com/css2?family=Roboto:wght@400;500&display=swap\" rel=\"stylesheet\"><style>body {display: block; margin: 0; background: #161e2d; color: #ffffff; font-family: \"Roboto\",sans-serif; font-size: 16px; font-weight: 400;} .container {display: flex; flex-direction: column; position: absolute; top: 42px; bottom: 0; left: 0; right: 0;} .navbar {position: fixed; top: 0; left: 0; right: 0; z-index: 2; background: #500280} .navbar-header { font-weight: 500; font-size: 1.125rem; display: flex; flex-wrap: wrap; align-items: center; padding: 12px 16px; box-shadow: rgba(0, 0, 0, 0.2) 0px 3px 5px -1px, rgba(0, 0, 0, 0.14) 0px 6px 10px 0px, rgba(0, 0, 0, 0.12) 0px 1px 18px 0px;} .main-container {justify-content: center; align-items: center; display: flex; flex-direction: row; flex-wrap: wrap; padding: 16px;} .card {margin: 8px; max-width: 480px; box-shadow: rgba(0, 0, 0, 0.2) 0px 2px 1px -1px, rgba(0, 0, 0, 0.14) 0px 1px 1px 0px, rgba(0, 0, 0, 0.12) 0px 1px 3px 0px; transition: box-shadow 280ms cubic-bezier(0.4, 0, 0.2, 1); border-radius: 4px; display: block; position: relative;} .card-img {border-radius: 4px;}</style></head><body><div class=\"container\"><div class=\"navbar\"><div class=\"navbar-header\">DR-$DR_RUN_ID - $DR_LOCAL_S3_MODEL_PREFIX - $TOPIC</div></div><div class=\"main-container\">" > $DR_VIEWER_HTML

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


for c in $ROBOMAKER_CONTAINERS; do
    C_URL="/$c/stream?topic=${TOPIC}&quality=${QUALITY}&width=${WIDTH}&height=${HEIGHT}"
    C_IMG="<div class='card'><img class=\"card-img\" src=\"${C_URL}\"></img></div>"
    echo $C_IMG >> $DR_VIEWER_HTML
    echo "  location /$c { proxy_pass http://$c:8080; rewrite /$c/(.*) /\$1 break; }" >> $DR_NGINX_CONF
done

echo "</div></div></body></html>" >> $DR_VIEWER_HTML
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
  if [ "${DR_DOCKER_STYLE,,}" == "swarm" ];
  then
    sleep 5
  fi
  $BROWSER "http://127.0.01:8100" &
fi

