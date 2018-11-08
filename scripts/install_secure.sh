#!/bin/bash
# This script installs the secure rpms

# Required arguments
usage() { 
    echo "IMPORTANT! Enclose the password in single quotes to make sure that special characters are escaped.
    Usage: $0 -p '<netmail password>'" 1>&2; exit 1; 
}

while getopts ":p:" o; do
    case "${o}" in
        p)
            ADMIN_PASSWD=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${ADMIN_PASSWD}" ]; then
    usage
    exit 1
fi

# PREPARE PLATFORM
sudo yum install epel-release -y
sudo yum install -y gettext sshpass jq cifs-utils gdb bind-utils wget screen net-tools sudo telnet nmap tcpdump rsync python python-libs

sudo useradd netmail -m
echo ${ADMIN_PASSWD} | sudo passwd netmail --stdin
sudo sh -c 'echo "netmail ALL=(ALL)    NOPASSWD: ALL" >> /etc/sudoers'

# INSTALL PLATFORM
PLATFORM_RPM="CENTOS-NETMAIL-PLATFORM-6.2.1.844_release-Linux.rpm"
SECURE_RPM="CENTOS-NETMAIL-SECURE-6.2.1.844_release-Linux.rpm"
wget --no-check-certificate \
    https://netgovernpkgs.blob.core.windows.net/download/${PLATFORM_RPM}
wget --no-check-certificate \
    https://netgovernpkgs.blob.core.windows.net/download/${SECURE_RPM}

sudo yum localinstall -y ${PLATFORM_RPM} ${SECURE_RPM}

#Rename VM to ensure unique names in the cluster
NEW_HOST_NAME=`curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-12-01" | jq -r '.compute' | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" | grep name | awk -F'=' '{ print $2 }'`
nmcli general hostname ${NEW_HOST_NAME,,} # ,, makes it lowercase
systemctl restart systemd-hostnamed

systemctl restart netmail
