#!/bin/bash
yum install samba samba-client samba-common -y
cat /dev/null > /etc/samba/smb.conf
cat <<EOF >/etc/samba/smb.conf

[global]
	workgroup = WORKGROUP
	security = user
	passdb backend = tdbsam
	log file = /var/log/samba/%m
	log level = 1

EOF

systemctl enable smb.service
systemctl enable nmb.service
systemctl restart smb.service
systemctl restart nmb.service

systemctl enable firewalld
systemctl restart firewalld
firewall-cmd --permanent --zone=public --add-service=samba
firewall-cmd --reload
 


