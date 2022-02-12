# Watching the car

There are multiple ways to watch the car during training and evaluation. The ports and 'features' depend on the docker mode (swarm vs. compose) as well as between training and evaluation.

## Training using Viewer

DRfC has a built in viewer that supports showing the video stream from up to 6 workers on one webpage.

The view can be started with `dr-start-viewer` and is available on `http://localhost:8100` or `http://127.0.0.1:8100`. The viewer must be updated if training is restarted using `dr-update-viewer`, as it needs to connect to the new containers.

It is also possible to automatically start/update the viewer using the `-v` flag to `dr-start-training`.

## ROS Stream Viewer

The ROS Stream Viewer is a built in ROS feature that will stream any topic in ROS that publishing ROSImg messages. The viewer starts automatically.

### Ports

| Docker Mode  | Training         | Evaluation      | Comment
| -------- | -------- | -------- | -------- | 
| swarm      | 8080 + `DR_RUN_ID` |  8180 + `DR_RUN_ID` | Default 8080/8180. Multiple workers share one port, press F5 to cycle between them.
| compose | 8080-8089 | 8080-8089 | Each worker gets a unique port.

### Topics

| Topic  | Description         | 
| -------- | -------- | 
| `/racecar/camera/zed/rgb/image_rect_color`      | In-car video stream. This is used for inference. | 
| `/racecar/main_camera/zed/rgb/image_rect_color`      | Camera following the car. Stream without overlay | 
| `/sub_camera/zed/rgb/image_rect_color`      | Top-view of the track | 
| `/racecar/deepracer/kvs_stream`      | Camera following the car. Stream with overlay. Different overlay in Training and Evaluation | 
| `/racecar/deepracer/main_camera_stream`      | Same as `kvs_stream`, topic used for MP4 production. Only active in Evaluation if `DR_EVAL_SAVE_MP4=True` | 

## Saving Evaluation to File

During evaluation (`dr-start-evaluation`), if `DR_EVAL_SAVE_MP4=True` then three MP4 files are created in the S3 bucket's MP4 folder. They contain the in-car camera, top-camera and the camera following the car.