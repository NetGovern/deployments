#!/bin/bash
# This script configures ldap from a NetGovern index VM.
# The ldap service are managed by launcher, which is launched by the service: netmail.
# Required arguments
usage() { 
    echo "IMPORTANT! Enclose the password in single quotes to make sure that special characters are escaped.
    Usage: $0 -r '<ldap root password>' -c '<cloudadmin password>' -n '<nipe password>'" 1>&2; exit 1; 
}

WaitUntilDead()
{
        # Try killing nicely
        tries=0
        while [ $tries -lt 15 ]; do
                killall $1 2>/dev/null || return 0

                ((tries++))
                sleep 1
        done

        # Okay, no more mister nice guy
        while killall -9 $1 2> /dev/null; do
                sleep 1
        done

        return 0
}

WaitForSlapd()
{
        tries=0
        while [ $tries -lt 300 ]; do
                ldapwhoami -H ldap:/// -x -D "cn=eclients,cn=system,o=netmail" -w "${ECLIENTS}" > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                        return 0
                fi
                ((tries++))
                sleep 1
        done

        return 1
}

while getopts ":r:c:n:" o; do
    case "${o}" in
        r)
            ADMIN_PASSWD=${OPTARG}
            ;;
        c)
            CLOUD_ADMIN_PASSWD=${OPTARG}
            ;;
        n)
            NIPE_PASSWD=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${ADMIN_PASSWD}" ] || [ -z "${CLOUD_ADMIN_PASSWD}" ] || [ -z "${NIPE_PASSWD}" ]; then
    usage
    exit 1
fi

# UNINSTALL INDEX
RPM=$(rpm -qa | grep netmail-index)
sudo yum erase -y ${RPM}

#if Azure, rename VM to ensure unique names in the cluster
NEW_HOST_NAME=`curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-12-01" | jq -r '.compute' | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" | grep name | awk -F'=' '{ print $2 }'`
if [ -z "$NEW_HOST_NAME" ]; then
    echo "Using image name"
else
    nmcli general hostname ${NEW_HOST_NAME,,} # ,, makes it lowercase
    systemctl restart systemd-hostnamed
fi

ECLIENTS=${ADMIN_PASSWD}
PASS=${ADMIN_PASSWD}

LOCALIP=`hostname -I | xargs`
HOST=`hostname -s`

# set up certificates/keys
mkdir -p /opt/ma/netmail/var/openldap/certs
openssl req -newkey rsa:2048 -x509 -nodes -out /opt/ma/netmail/var/openldap/certs/openldap.crt -keyout /opt/ma/netmail/var/openldap/certs/openldap.key -days 3650 -subj "/CN=${LOCALIP}/O=netmail/C=CA"
cp -f /opt/ma/netmail/var/openldap/certs/openldap.crt /opt/ma/netmail/var/openldap/certs/${LOCALIP}.crt
ln -s /opt/ma/netmail/var/openldap/certs/${LOCALIP}.crt /opt/ma/netmail/var/openldap/certs/`openssl x509 -noout -hash -in /opt/ma/netmail/var/openldap/certs/${LOCALIP}.crt`.0

# write slapd config
mkdir -p /opt/ma/netmail/var/openldap/data
>/opt/ma/netmail/etc/slapd-multimaster.conf
cat <<EOF >/opt/ma/netmail/etc/slapd.conf
include         /etc/openldap/schema/core.schema
include         /opt/ma/netmail/etc/netmail.schema.ldif

pidfile         /opt/ma/netmail/var/openldap/slapd.pid
argsfile        /opt/ma/netmail/var/openldap/slapd.args

include /opt/ma/netmail/etc/slapd-access.conf

database        mdb
maxsize         10737418240
suffix          "o=netmail"
rootdn                  "cn=eclients,cn=system,o=netmail"
rootpw                  "${ECLIENTS}"

directory       /opt/ma/netmail/var/openldap/data

index   entryCSN        eq
index   entryUUID       eq
index   objectClass     eq
index   uid             pres,eq
index   mail            pres,sub,eq
index   cn              pres,sub,eq
index   sn              pres,sub,eq
index   dc              eq

sizelimit unlimited

TLSCACertificateFile /opt/ma/netmail/var/openldap/certs/openldap.crt
TLSCertificateFile /opt/ma/netmail/var/openldap/certs/openldap.crt
TLSCertificateKeyFile /opt/ma/netmail/var/openldap/certs/openldap.key
TLSCipherSuite ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384:DHE-RSA-AES256-SHA384:ECDHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA256:HIGH:!aNULL:!eNULL:!EXPORT:!3DES:!DES:!RC4:!MD5:!PSK:!SRP:!CAMELLIA
TLSProtocolMin 3.2
TLSVerifyClient never

limits dn.exact="cn=eclients,cn=system,o=netmail" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
include /opt/ma/netmail/etc/slapd-multimaster.conf
EOF
cat <<'EOF' >/opt/ma/netmail/var/openldap/data/DB_CONFIG
# $OpenLDAP$
# Example DB_CONFIG file for use with slapd(8) BDB/HDB databases.
#
# See the Oracle Berkeley DB documentation
#   <http://www.oracle.com/technology/documentation/berkeley-db/db/ref/env/db_config.html>
# for detail description of DB_CONFIG syntax and semantics.
#
# Hints can also be found in the OpenLDAP Software FAQ
#       <http://www.openldap.org/faq/index.cgi?file=2>
# in particular:
#   <http://www.openldap.org/faq/index.cgi?file=1075>

# Note: most DB_CONFIG settings will take effect only upon rebuilding
# the DB environment.

# one 0.25 GB cache
set_cachesize 0 268435456 1

# Data Directory
#set_data_dir db

# Transaction Log settings
set_lg_regionmax 262144
set_lg_bsize 2097152
#set_lg_dir logs

# Note: special DB_CONFIG flags are no longer needed for "quick"
# slapadd(8) or slapindex(8) access (see their -q option).
EOF
cat <<EOF >/opt/ma/netmail/etc/slapd-access.conf

access to *
	by *	write


EOF
# start slapd
WaitUntilDead slapd
slapd -f /opt/ma/netmail/etc/slapd.conf -h ldap:///
WaitForSlapd

cat <<EOF >/tmp/baseobjects.ldif
dn: o=netmail
objectClass: organization
o: netmail
description: Root netmail object

dn: cn=system,o=netmail
objectClass: maSystem
cn: system

dn: cn=netmail,cn=system,o=netmail
objectClass: maUser
cn: netmail
sn: netmail

dn: cn=cloudadmin,cn=system,o=netmail
objectClass: maUser
cn: cloudadmin
sn: cloudadmin

dn: cn=multitennipe,o=netmail
objectClass: maUser
cn: multitennipe
sn: multitennipe

EOF
cat /tmp/baseobjects.ldif | \
        ldapadd -H ldap:/// -x \
        -D "cn=eclients,cn=system,o=netmail" -w "${ECLIENTS}"
ldappasswd -H ldap:/// -x \
        -D "cn=eclients,cn=system,o=netmail" -w "${ECLIENTS}" \
        -s "${PASS}" "cn=netmail,cn=system,o=netmail"
ldappasswd -H ldap:/// -x \
        -D "cn=eclients,cn=system,o=netmail" -w "${ECLIENTS}" \
        -s "${CLOUD_ADMIN_PASSWD}" "cn=cloudadmin,cn=system,o=netmail"
ldappasswd -H ldap:/// -x \
        -D "cn=eclients,cn=system,o=netmail" -w "${ECLIENTS}" \
        -s "${NIPE_PASSWD}" "cn=multitennipe,o=netmail"

rm -f /tmp/baseobjects.ldif

# stop slapd
WaitUntilDead slapd

echo "Configuring SLAPD/launcher service"
sudo pkill slapd
sudo mv /opt/ma/netmail/etc/launcher.d/01-traps.conf /opt/ma/netmail/etc/launcher.d-available/
sudo mv /opt/ma/netmail/etc/launcher.d/92-autobackup.conf /opt/ma/netmail/etc/launcher.d-available/
# Add ldap as as a service managed by launcher
echo "group set \"NetGovern Directory\" \"NetGovern Directory\"" | sudo tee /opt/ma/netmail/etc/launcher.d/05-openldap.conf
echo "start -priority 1 slapd -d 0 -f /opt/ma/netmail/etc/slapd.conf -h \"ldapi:/// ldap:/// ldaps:///\"" | sudo tee -a /opt/ma/netmail/etc/launcher.d/05-openldap.conf

sudo systemctl restart netmail

echo "Configuring Firewall"
#Checking Firewalld State and Status
FWSTATE=`systemctl is-enabled firewalld`
if [ "${FWSTATE}" != "enabled" ]; then
    systemctl enable firewalld
fi

FWSTATUS=`systemctl is-active firewalld`
if [ "${FWSTATUS}" != "active" ]; then
    systemctl start firewalld
fi

echo "Opening ldap ports 389 and 636"
firewall-cmd --permanent --add-port=389/tcp
firewall-cmd --permanent --add-port=636/tcp

systemctl reload firewalld

exit 0