#!/bin/bash
# This script configures a shared location and a local user account for an existing SAMBA server.
# Required arguments
usage() { 
    echo "IMPORTANT! Enclose the password in single quotes to make sure that special characters are escaped.
    Usage: $0 -u <newuser> -p '<newuserpassword>' -s <newsharename> -b </path/to/base>" 1>&2; exit 1; 
}

while getopts ":u:p:s:b:" o; do
    case "${o}" in
        u)
            NEW_USER=${OPTARG}
            ;;
        p)
            NEW_USER_PASSWD=${OPTARG}
            ;;
        s)
            NEW_SHARE_NAME=${OPTARG}
            ;;
        b)
            PATH_TO_BASE=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${NEW_USER}" ] || [ -z "${NEW_USER_PASSWD}" ] || [ -z "${NEW_SHARE_NAME}" ] || [ -z "${PATH_TO_BASE}" ]; then
    usage
    exit 1
fi

sudo useradd -M -s /sbin/nologin ${NEW_USER}
echo ${NEW_USER_PASSWD} | sudo passwd ${NEW_USER} --stdin
echo ${NEW_USER_PASSWD} | sudo smbpasswd -a ${NEW_USER} --stdin
sudo smbpasswd -e ${NEW_USER}

sudo groupadd ${NEW_USER}Group
sudo usermod -aG ${NEW_USER}Group ${NEW_USER}

sudo mkdir -p /${PATH_TO_BASE}/${NEW_SHARE_NAME}/

sudo chgrp -R ${NEW_USER}Group /${PATH_TO_BASE}/${NEW_SHARE_NAME}/

sudo chmod 2770 /${PATH_TO_BASE}/${NEW_SHARE_NAME}/

sudo chcon -t samba_share_t /${PATH_TO_BASE}/${NEW_SHARE_NAME}/

cat <<EOF >>/etc/samba/smb.conf

[${NEW_SHARE_NAME}]
        # This share requires authentication to access
        path = /${PATH_TO_BASE}/${NEW_SHARE_NAME}/
        read only = no
        guest ok = no

EOF

sudo systemctl restart smb.service
sudo systemctl restart nmb.service