# Library for Azure specific functions
#
# This file is sourced by the main script and contains functions that are specific to Azure.
# It is sourced after the common libraries and before the main script.


# Azure specific functions
#-----------------------------------------------------------------------------------------------------------------------
function prepare_additional_disk() {
  # Function to prepare an additional disk for use

    ADDL_DISK=$(lsblk | awk '/^sdc/ {print $1}')
    ADDL_PART=$(lsblk -l | awk -v DISK="$ADDL_DISK" '($0 ~ DISK) && ($0 ~ /part/) {print $1}')

    if [ -n "$ADDL_DISK" ] && [ -z "$ADDL_PART" ];
    then
        log_message info "Found $ADDL_DISK, preparing it for use"
        echo -e "g\nn\np\n1\n\n\nw\n" | sudo fdisk /dev/$ADDL_DISK
        sleep 1s
        ADDL_DEVICE=$(echo "/dev/"$ADDL_DISK"1")
        sudo mkfs.ext4 $ADDL_DEVICE
        sudo mkdir -p /var/lib/docker
        echo "$ADDL_DEVICE   /var/lib/docker   ext4    rw,user,auto    0    0" | sudo tee -a /etc/fstab
        mount /var/lib/docker
        if [ $? -ne 0 ]
        then
            log_message info "Error during preparing of additional disk. Exiting."
            exit 1
        fi
    elif [ -n "$ADDL_DISK" ] && [ -n "$ADDL_PART" ];
    then
        log_message info "Found $ADDL_DISK - $ADDL_PART already mounted. Installing into present drive/directory structure."
    else
        log_message info "Did not find $ADDL_DISK. Installing into present drive/directory structure."
    fi
}