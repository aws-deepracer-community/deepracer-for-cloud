import os
import argparse
import time
import sys


def get_folder_size(folder):
    total_size = os.path.getsize(folder)
    for item in os.listdir(folder):
        itempath = os.path.join(folder, item)
        if os.path.isfile(itempath):
            total_size += os.path.getsize(itempath)
        elif os.path.isdir(itempath):
            total_size += get_folder_size(itempath)
    return total_size


def handle_folder_files(path, name, max_size):
    if os.path.exists(path):
        size = get_folder_size(path) / 1000000000  # directory size in GB
        print("Size of " + name + " path directory: " + str(size) + "GB" + " capped at " + str(max_size) + "GB")

        if size > max_size:
            file_list = []
            for file in os.listdir(path):
                file_list.append([os.stat(os.path.join(path, file)).st_mtime, os.path.join(path, file)])
            file_list.sort(key=lambda x: x[0])  # sort by creation date, delete the old files first
            if os.path.basename(file_list[0][1]) != "model_metadata.json":
                os.remove(file_list[0][1])
                print("Removed: " + os.path.basename(file_list[0][1]))
            else:
                os.remove(file_list[1][1])
                print("Removed: " + os.path.basename(file_list[1][1]))


def manage_memory(args):
    model_path = os.path.join(os.path.split(os.path.abspath(__file__))[0], "../../docker/volumes/minio/bucket/rl-deepracer-sagemaker/model/")
    checkpoint_path = os.path.join(os.path.split(os.path.abspath(__file__))[0], "../../docker/volumes/robo/checkpoint/checkpoint/")
    while True:
        handle_folder_files(model_path, "model", args.sagemaker_model_cap)
        handle_folder_files(checkpoint_path, "checkpoint", args.checkpoint_cap)
        print("")

        time.sleep(30)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Manage memory usage of local DeepRacer by capping the memory usage of key folders")
    parser.add_argument('-m', '--sagemaker_model_cap',
                        help="The cap size (in GB) for the model folder in volumes/minio/bucket/rl-deepracer-sagemaker/model/",
                        type=float, default=3)
    parser.add_argument('-c', '--checkpoint_cap',
                        help="The cap size (in GB) for the model folder in volumes/robo/checkpoint/checkpoint/",
                        type=float, default=3)
    args = parser.parse_args()
    manage_memory(args)
