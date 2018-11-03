#!/usr/bin/bash
# This script installs postgresql, opens the firewall ports needed and allows access to the requested network
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

# postgresql installation
yum install -y \
    epel-release
yum install -y \
     postgresql-server postgresql-contrib

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

echo "Allowing ${CIDR} for Postgres port 5432"
firewall-cmd --permanent --add-rich-rule='
    rule family=ipv4
    source address='${CIDR}'
    port port=5432 protocol=tcp accept'

systemctl reload firewalld
systemctl restart postgresql


