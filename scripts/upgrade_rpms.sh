#!/bin/bash
# This script upgrades rpms

# Required arguments
usage() { 
    echo "IMPORTANT! Enclose the password in single quotes to make sure that special characters are escaped.
    Usage: $0 -v '<netmail version>'
    [-i]    Installs index RPM
    [-s]    Installs secure RPM
    " 1>&2; exit 1; 
}

# Default Values
SECURE=0
INDEX=0
INDEX_RPM=""
SECURE_RPM=""

while getopts ":v:si" o; do
    case "${o}" in
        v)
            NETMAIL_VERSION=${OPTARG}
            ;;
        s)
            SECURE=1
            ;;
        i)
            INDEX=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${NETMAIL_VERSION}" ]; then
    usage
    exit 1
fi

# Download and install RPMs
PLATFORM_RPM="CENTOS-NETMAIL-PLATFORM-${NETMAIL_VERSION}_release-Linux.rpm"
wget --no-check-certificate \
    https://netgovernpkgs.blob.core.windows.net/download/${PLATFORM_RPM}

if [ ${INDEX} -eq 1 ]; then
    INDEX_RPM="CENTOS-NETMAIL-INDEX-${NETMAIL_VERSION}_release-Linux.rpm"
    wget --no-check-certificate \
        https://netgovernpkgs.blob.core.windows.net/download/${INDEX_RPM}
fi

if [ ${SECURE} -eq 1 ]; then
    SECURE_RPM="CENTOS-NETMAIL-SECURE-${NETMAIL_VERSION}_release-Linux.rpm"
    wget --no-check-certificate \
        https://netgovernpkgs.blob.core.windows.net/download/${SECURE_RPM}
fi

sudo yum install epel-release -y
sudo yum localinstall -y ${PLATFORM_RPM} ${INDEX_RPM} ${SECURE_RPM}