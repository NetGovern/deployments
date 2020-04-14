usage() { 
    echo "IMPORTANT! Enclose the password in single quotes to make sure that special characters are escaped.
    Usage: $0 '<ldap root password>'" 1>&2; exit 1; 
}

if [ -z "${1}" ]; then
    usage
    exit 1
fi

LOCALIP=`hostname -I | xargs`
HOST=`hostname -s`

# write mdb.conf
cat <<EOF >/opt/ma/netmail/etc/mdb.conf
Driver=MDBLDAP machine=${HOST}&basedn=o%3Dnetmail
    ldap://${LOCALIP}#0
EOF

echo -n ${1} > /opt/ma/netmail/var/dbf/eclients.dat

# Add portal as a service managed by launcher
echo "group set \"NetGovern Portal\" \"NetGovern Portal\"" | sudo tee /opt/ma/netmail/etc/launcher.d/20-portal.conf
echo "# The portal service depends on NetGovern Admin" | sudo tee -a /opt/ma/netmail/etc/launcher.d/20-portal.conf
echo "group qstart \"NetGovern Admin\"" | sudo tee -a /opt/ma/netmail/etc/launcher.d/20-portal.conf
echo "# Portal" | sudo tee -a /opt/ma/netmail/etc/launcher.d/20-portal.conf
echo "start -name portal node ../../../../node_modules/netmail/portal" | sudo tee -a /opt/ma/netmail/etc/launcher.d/20-portal.conf

# Check if 10-netmail.conf is enabled
if [ ! -f /opt/ma/netmail/etc/launcher.d/10-netmail.conf ]; then
    mv /opt/ma/netmail/etc/launcher.d-available/10-netmail.conf /opt/ma/netmail/etc/launcher.d/
fi

echo "Configuring CFS"
sudo /opt/ma/netmail/etc/scripts/setup/ConfigureCFS new ${LOCALIP}

firewall-cmd --permanent --add-port=8000/tcp
sudo systemctl reload firewalld

sudo systemctl restart netmail