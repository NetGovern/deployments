# Multitenant cluster setup script

Prepare vms with preinstalled Netgovern, but no set yet. For Linux part you can use index vm. Make sure you have the latest build, if you use 6.5 ova images, update manually to latest.
Before you start, makes sure you open Internet Explorer at least once before you start setup! Otherwise script wont be able to generate the required api keys.
Take a note of all password you use. You will need them in most of the steps.

## LDAP setup
 
* Copy the script "configure_ldap_single.sh" from Linux folder in /home/netmail
* Login as netmail and run sudo yum install -y dos2unix && dos2unix configure_ldap_single.sh && chmod +x configure_ldap_single.sh
* after that run sudo ./configure_ldap_single.sh -r M3ss4g1ng -c M3ss4g1ng -n M3ss4g1ng , change the passwords accordingly  and write them down. Password1 - LDAP admin, Password2 - CloudAdmin, Password3 - NipePassword
* Make sure services are running systemctl status netmail_ , check connectivity with LDAP browser or command line
## Set the shared index
* Copy the script "solr_config.sh" from Linux folder in /home/netmail
* Login as netmail and run sudo yum install -y dos2unix && dos2unix solr_config.sh && chmod +x solr_config.sh
* After that run sudo ./solr_config.sh -q
* Check if the services are running. Test the solr admin page ip:31000
## Set Postgres
* Copy the script "install_postgresql.sh" from Linux folder in /home/netmail
* Login as netmail and run sudo yum install -y dos2unix && dos2unix install_postgresql.sh && chmod +x install_postgresql.sh
* After that run sudo ./install_postgresql.sh -p M3ss4g1ng -n x.x.x.0/24 .  Write down the password. This postgres user pw. Change the network accordingly
* Check the services systemctl status postgresql
* Try to connect with PGadmin
## Setup DP
* Copy the Windows folder to DP. From DP node start PS as Administrator, from the folder with the scripts run             .\NewRemoteProvider.ps1 -ldap_server "x.x.x.x" -multitennipe_password "M3ss4g1ng" -linux_admin_password "M3ss4g1ng" -linux_admin_user "netmail" -zookeeper_ip "x.x.x.x".  Use the passwords you set earlier, linux admin is "netmail" user in our vms
## Setup Master for each tenant
* Copy the Windows folder to Master. From Master node start PS as Administrator, from the folder with the scripts run          .\MasterSetupWizard.ps1 -ldap_server "x.x.x.x" -ldap_admin_dn 'cn=netmail,cn=system,o=netmail' -ldap_admin_password "M3ss4g1ng" -zookeeper_ip "x.x.x.x" -postgresql_server "x.x.x.x" -postgresql_admin_password "M3ss4g1ng" -tenant_id "tenant01" -netgovern_password "M3ss4g1ng" -o365_user "nicks@netmail.onmicrosoft.com" -o365_password "123Password" -ma_notify_email "nicks@netmail.onmicrosoft.com" -remote_provider_ip_address "x.x.x.x" -remote_provider_admin_user "administrator" -remote_provider_password "123Password" -o365_tenat_id "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"         .                  Replace x.x.x.x with relevant IP, so with the passwords and 365 tenant id. For Onprem setup you need to use AD IP,  change the exchange PS end point - open the script in editor to see the proper parameter names
* Make sure the services are started
* Check the User sync is OK
* Do a test archive job. If you cannot select user, delete the users in platform cache and run user sync again. Make sure you have the user in platform cache in LDAP and solar platfor_users collection.
## Setup Crawler for each tenant/master node
* Copy the Windows folder to Crawler. From Crawler node start PS as Administrator, from the folder with the scripts run        .\ConfigureCrawler.ps1 -master_server_address x.x.x.x -master_admin_user administrator -master_admin_password 123Password -netmail_user_password M3ss4g1ng -postgres_password M3ss4g1ng -rp_server_address x.x.x.x -rp_admin_user administrator -rp_admin_password 123Password        .   Replace x.x.x.x with relevant IP, so with the passwords. Make sure service on all involved nodes are restarted, the script does it, but it may happens to fail.
* Run Test crawler jobs.
