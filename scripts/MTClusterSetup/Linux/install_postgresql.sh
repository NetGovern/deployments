#!/usr/bin/bash
# This script installs postgresql, opens the firewall ports needed and allows access to the requested network
#It will ask for confirmation to uninstall NetGovern rpms. To automate the answe you can do "echo <y or n> | script
#If you set up postgres with another NetGovern product, DO NOT unistall rpm, only if postgres is standalone 
# Required arguments
usage() { 
    echo "Usage: $0 -p <postgres password> -n <CIDR network to allow>" 1>&2; exit 1; 
}

while getopts ":p:n:" o; do
    case "${o}" in
        p)
            POSTGRES_PASSWD=${OPTARG}
            ;;
        n)
            CIDR=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${POSTGRES_PASSWD}" ] || [ -z "${CIDR}" ]; then
    usage
fi
#IB remove netmail packs
while true; do
    read -p "Do you want to uninstall NetGovern rpms?(y/n): " yn
    case $yn in
        [Yy]* ) rpm -e ` rpm -qa | grep netmail`  && rm -fr /opt/ma/netmail && rm -rf /var/netmail; break;;
        [Nn]* ) echo "You choose to not uninstall"; break;;
        * ) echo 'Please answer "y" or "n".';;
    esac
done

# postgresql installation
yum install -y \
    epel-release
yum install -y \
     postgresql-server postgresql-contrib firewalld

# Configure Locale to UTF8 
sudo localectl set-locale LANG=en_US.UTF-8

#Initialize Server
postgresql-setup initdb

systemctl start postgresql
systemctl enable postgresql

echo "Configuring listeners"
sed -i \
    's/#listen_addresses = \x27localhost\x27/listen_addresses = \x27*\x27/g' \
    /var/lib/pgsql/data/postgresql.conf

echo "Changin postgres password"
echo ${POSTGRES_PASSWD} | sudo passwd postgres --stdin
sudo -u postgres -i psql -d template1 -c "ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWD}';"

echo "Allowing ${CIDR}"
echo "host   all   all   ${CIDR}   md5" | sudo tee -a /var/lib/pgsql/data/pg_hba.conf

#Checking Firewalld State and Status
FWSTATE=`systemctl is-enabled firewalld`
if [ "${FWSTATE}" != "enabled" ]; then
    systemctl enable firewalld
fi

FWSTATUS=`systemctl is-active firewalld`
if [ "${FWSTATUS}" != "active" ]; then
    systemctl start firewalld
fi

echo "Opening Postgres port 5432"
firewall-cmd --permanent --add-port=5432/tcp

systemctl reload firewalld
systemctl restart postgresql


