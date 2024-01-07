# About the Docker setup

DRfC supports running Docker in to modes `swarm` and `compose` - this behaviour is configured in `system.env` through `DR_DOCKER_STYLE`.

## Swarm Mode

Docker Swarm mode is the default. Docker Swarm makes it possible to connect multiple hosts together to spread the load -- esp. useful if one wants to run multiple Robomaker workers, but can also be useful locally if one has two computers that each are not powerful enough to run DeepRacer.

In Swarm mode DRfC creates Stacks, using `docker stack`. During operations one can check running stacks through `docker stack ls`, and running services through `docker stack <id> ls`.

DRfC is installed only on the manager. (The first installed host.) Swarm workers are 'dumb' and do not need to have DRfC installed.

### Key features

* Allows user to connect multiple computers on the same network. (In AWS the instances must be connected on same VPC, and instances must be allowed to communicate.)
* Supports [multiple Robomaker workers](multi_worker.md)
* Supports [running multiple parallel experiments](multi_run.md)

### Limitations

* The Sagemaker container can only be run on the manager.
* Docker images are downloaded from Docker Hub. Locally built images are allowed only if they have a unique tag, not in Docker Hub. If you have multiple Docker nodes ensure that they all have the image available.

### Connecting Workers

* On the manager run `docker swarm join-token manager`.
* On the worker run the command that was displayed on the manager `docker swarm join --token <token> <ip>:<port>`.

### Ports

Docker Swarm will automatically put a load-balancer in front of all replicas in a service. This means that the ROS Web View, which provides a video stream of the DeepRacer during training, will be load balanced - sharing one port (`8080`). If you have multiple workers (even across multiple hosts) then press F5 to cycle through them. 

## Compose Mode

In Compose mode DRfC creates Services, using `docker compose`. During operations one can check running stacks through `docker service ls`, and running services through `docker service ps`.

### Key features

* Supports [multiple Robomaker workers](multi_worker.md)
* Supports [running multiple parallel experiments](multi_run.md)
* Supports [GPU Accelerated OpenGL for Robomaker](opengl.md)

### Limitations

* Workload cannot be spread across multiple hosts.

### Ports

In the case of using Docker Compose the different Robomaker worker will require unique ports for ROS Web Vew and VNC. Docker will assign these dynamically. Use `docker ps` to see which container has been assigned which ports.
