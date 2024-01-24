# GPU Accelerated OpenGL for Robomaker

One way to improve performance, especially of Robomaker, is to enable GPU-accelerated OpenGL. OpenGL can significantly improve Gazebo performance, even where the GPU does not have enough GPU RAM, or is too old, to support Tensorflow.

## Desktop 

On a Ubuntu desktop running Unity there are hardly any additional steps required.

* Ensure that a recent Nvidia driver is installed and is running.
* Ensure that nvidia-docker is installed; review `bin/prepare.sh` for steps if you do not want to directly run the script.
* Configure DRfC using the following settings in `system.env`:
    * `DR_HOST_X=True`; uses the local X server rather than starting one within the docker container.
    * `DR_DISPLAY`; set to the value of your running X server, if not set then `DISPLAY` will be used.

Before running `dr-start-training`/`dr-start-evaluation` ensure that `DR_DISPLAY`/`DISPLAY` and `XAUTHORITY` are defined.

Check that OpenGL is working by looking for `gzserver` in `nvidia-smi`.

If `DR_GUI_ENABLE=True` then the Gazebo UI, rviz and rqt will open up in separate windows. (With multiple workers it can get crowded...)

### Remote connection to Desktop 

If you want to start training or evaluation via SSH (e.g. to increment the training whilst you are on the go) there are a few steps to do:
* Ensure that you are actually logged in to the local machine (desktop session is running).
* In the SSH terminal:
    * Ensure `DR_DISPLAY` is configured in `system.env`. Otherwise run `export DISPLAY=:1`. [*]
    * Run `export XAUTHORITY=/run/user/$(id -u)/gdm/Xauthority` to let X know where the X magic cookie is.
    * Run `source bin/activate.sh` as normal.
    * Run your `dr-start-training` or `dr-start-evaluation` command. 

*Remark*: Setting `DISPLAY` will lead to certain commands (e.g. `dr-logs-sagemaker`) starting in a terminal window on the desktop, rather than the output being showhn in the SSH terminal.
Use of `DR_DISPLAY` is recommended to avoid this.

## Headless Server

Also a headless server with a GPU, e.g. an EC2 instance, or a local computer with a displayless GPU (e.g. Tesla K40, K80, M40).

This also applies for a desktop computer where you are not logged in. In this case also disconnect any monitor cables to avoid conflict.

* Ensure that a Nvidia driver and nvidia-docker is installed; review `bin/prepare.sh` for steps if you do not want to directly run the script.
* Setup an X-server on the host. `utils/setup-xorg.sh` is a basic installation script.
* Configure DRfC using the following settings in `system.env`:
    * `DR_HOST_X=True`; uses the local X server rather than starting one within the docker container.
    * `DR_ROBOMAKER_IMAGE`; choose the tag for an OpenGL enabled image - e.g. `cpu-gl-avx` for an image where Tensorflow will use CPU or `gpu-gl` for an image where also Tensorflow will use the GPU.
    * `DR_DISPLAY`; the X display that the headless X server will start on. (Default is `:99`, avoid using `:0` or `:1` as it may conflict with other X servers.)

Start up the X server with `utils/start-xorg.sh`. 

If `DR_GUI_ENABLE=True` then a VNC server will be started on port 5900 so that you can connect and interact with the Gazebo UI.

Check that OpenGL is working by looking for `gzserver` in `nvidia-smi`.
