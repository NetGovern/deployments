#!/bin/bash
yum install epel-release -y
yum install jq -y
NEW_HOST_NAME=`curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-12-01" | jq -r '.compute' | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" | grep name | awk -F'=' '{ print $2 }'`
nmcli general hostname ${NEW_HOST_NAME}
systemctl restart systemd-hostnamed

: <<'ENDCOMMENT'
From Azure knowledge base
Device paths in Linux aren't guaranteed to be consistent across restarts. 
When the Linux storage device driver detects a new device, the driver assigns major and minor numbers from the available range to the device. 
When a device is removed, the device numbers are freed for reuse.
The problem occurs because device scanning in Linux is scheduled by the SCSI subsystem to happen asynchronously. 
As a result, a device path name can vary across restarts. 
ENDCOMMENT

#Detect disk without partitions
DISKS=`lsblk | grep "^sd" | awk -F' ' '{ print $1 }'`
while read -r LINE; do
    PROBE=`sudo partprobe -d -s /dev/${LINE}`
    if [ -z "${PROBE}" ]; then
        EMPTY_DISK="/dev/${LINE}"
    fi
done <<< "${DISKS}"

if [ -z $EMPTY_DISK ]; then
    echo "EMPTY DISK NOT FOUND"
    exit 2
fi

#Create mount point, partition, file system and mount it
mkdir /var/netmail
parted -s ${EMPTY_DISK} mklabel msdos
parted -s ${EMPTY_DISK} unit mib mkpart primary 1 100%
mkfs.btrfs ${EMPTY_DISK}1
UUID=`sudo -i blkid | grep ${EMPTY_DISK}1 | awk -F' ' '{ print $2 }' | awk -F'=' '{ print $2 }' | sed 's/"//g'`
echo "UUID=${UUID} /var/netmail                   btrfs     defaults        0 0" >> /etc/fstab
mount -a
