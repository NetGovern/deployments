#!/bin/bash
# This script upgrades rpms

# Required arguments
usage() { 
    echo "IMPORTANT! Enclose the password in single quotes to make sure that special characters are escaped.
    Usage: $0 -v '<netgovern version> [-p][-i][-s]'
    [-i]    Installs index RPM
    [-s]    Installs secure RPM
    [-p]    Installs platform RPM only
    " 1>&2; exit 1; 
}

# Default Values
SECURE=0
INDEX=0
PLATFORM=0
INDEX_RPM=""
SECURE_RPM=""

while getopts ":v:sip" o; do
    case "${o}" in
        v)
            NETGOVERN_VERSION=${OPTARG}
            ;;
        s)
            SECURE=1
            ;;
        i)
            INDEX=1
            ;;
        p)
            PLATFORM=1
            ;;  
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${NETGOVERN_VERSION}" ]; then
    usage
    exit 1
fi

if [[ ${NETGOVERN_VERSION} < "9.9.9.9" ]]; then # If (or when) RPMs change their name in future versions.  
                                                # Replace 9.9.9.9 with the version bringing the name change
    BRAND="NETMAIL"
else
    BRAND="NETGOVERN"
fi


# Download and install RPMs
PLATFORM_RPM="CENTOS-${BRAND}-PLATFORM-${NETGOVERN_VERSION}_release-Linux.rpm"
wget --no-check-certificate \
    https://netgovernpkgs.blob.core.windows.net/download/${PLATFORM_RPM}

if [ ${INDEX} -eq 1 ]; then
    INDEX_RPM="CENTOS-${BRAND}-INDEX-${NETGOVERN_VERSION}_release-Linux.rpm"
    wget --no-check-certificate \
        https://netgovernpkgs.blob.core.windows.net/download/${INDEX_RPM}
fi

if [ ${SECURE} -eq 1 ]; then
    SECURE_RPM="CENTOS-${BRAND}-SECURE-${NETGOVERN_VERSION}_release-Linux.rpm"
    wget --no-check-certificate \
        https://netgovernpkgs.blob.core.windows.net/download/${SECURE_RPM}
fi

sudo yum install epel-release -y
sudo yum localinstall -y ${PLATFORM_RPM} ${INDEX_RPM} ${SECURE_RPM}