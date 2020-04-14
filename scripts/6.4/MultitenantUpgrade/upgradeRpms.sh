# Netgovern rpms install
# It requires 4 parameters in the following order: PLATFORM_RPM_URL, PLATFORM_RPM_FILENAME, INDEX_RPM_URL, INDEX_RPM_FILENAME (each pair for each RPM to download)


if [ -z "$1" ]; then
    echo "No URL Provided to download platform rpm"
else
    PLATFORM_RPM_URL=$1
fi

if [ -z "$2" ]; then
    echo "No FileName Provided to download platform rpm"
else
    PLATFORM_RPM_FILENAME=$2
fi

if [ -z "$3" ]; then
    echo "No URL Provided to download index rpm"
else
    INDEX_RPM_URL=$3
fi

if [ -z "$4" ]; then
    echo "No FileName Provided to download index rpm"
else
    INDEX_RPM_FILENAME=$4
fi

RPMS_TO_INSTALL="${PLATFORM_RPM_FILENAME} ${INDEX_RPM_FILENAME}"

# DOWNLOAD + INSTALL NETGOVERN RPMS
if [ -z "$INDEX_RPM_FILENAME" ]; then
    echo "Skipping index"
else
    wget --no-check-certificate -O ${INDEX_RPM_FILENAME} ${INDEX_RPM_URL}
fi

if [ -z "$PLATFORM_RPM_FILENAME" ]; then
    echo "Skipping platform"
else
    wget --no-check-certificate -O ${PLATFORM_RPM_FILENAME} ${PLATFORM_RPM_URL}
fi

sudo yum localinstall -y ${RPMS_TO_INSTALL}