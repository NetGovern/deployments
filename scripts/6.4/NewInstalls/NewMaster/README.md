# Adding a new tenant

This document describes the procedure to add a new tenant to an existing "Pod".  

First of all, we need to gather the network and credentials information for the shared layer infrastructure that defines our existing Pod:  

* **LDAP Server IP address, Admin DN and password**:  
    They are needed to create the subtree that will contain most of the new tenant configuration
* **Zookeeper/Solr/Index IP address**:  
    The Zookeeper IP address, usually the first node if more than 1 index has been deployed
* **PostgreSQL server IP address, port (if not 5432), admin user and password**:
    It will be used to create and configure the DB and credentials that will be used by the new tenant
* **Tenant ID**: 
    The unique tenant ID. It should match the one present in the new license.  
* **Netmail Password**: 
    The new password that the new admin account will have for the UI
* **Remote Provider IP address, admin account and password**:
    The Remote Provider where the new Netmail Search web application will be created.  The Administrator account has to be able to map the administrative C$ shared drive.
* **Smtp server address**: The smtp server used by netmail search
* **O365 Credentials**: (Not mandatory, it can be changed in the UI after)  
    The login information to access O365 Porwershell URL.
* **Notify**: (Not mandatory, it can be changed in the UI after)  
    The email to receive job status notifications

---

### You can download the below zip file containing the scripts listed below and unzip them in the same folder in the new archive master VM to be deployed.

<a href="https://github.com/NetGovern/deployments/blob/master/scripts/AddNewTenant/AddNewTenant.zip" target="_blank">AddNewTenant.zip</a>

Or


### You can download (Right-Click each link and select "Save As...") the following scripts/files to the same location in the new archive master VM to be deployed.  Make sure to Unblock them by right clicking on the downloaded files and choosing "Unblock"

* <a href="https://github.com/NetGovern/deployments/blob/master/scripts/MasterSetupWizard.ps1" target="_blank">MasterSetupWizard.ps1</a>
* <a href="https://github.com/NetGovern/deployments/blob/master/scripts/basedata.ps1" target="_blank">basedata.ps1</a>
* <a href="https://github.com/NetGovern/deployments/blob/master/scripts/ConfigureDP.ps1" target="_blank">ConfigureDP.ps1</a>
* <a href="https://github.com/NetGovern/deployments/blob/master/scripts/ngfunctions.ps1" target="_blank">ngfunctions.ps1</a>

---

### Running the scripts
The main script that drives the installation is *MasterSetupWizard.ps1*
It will call the rest of the scripts as needed.

Example of parameters used to run the configuration wizard 
```
.\MasterSetupWizard.ps1 -ldap_server 1.1.1.1 `
    -ldap_admin_dn 'cn=netmail,cn=system,o=netmail' `
    -ldap_admin_password TheLdapPassword `
    -zookeeper_ip 2.2.2.2 `
    -postgresql_server 3.3.3.3 `
    -postgresql_admin_password ThePostgresPassword `
    -tenant_id new_tenant `
    -netmail_password 'TheNetmailPa$$word' `
    -remote_provider_ip_address 4.4.4.4 `
    -remote_provider_admin_user administrator `
    -remote_provider_password TheRemoteProviderPassword `
    -smtp_server 5.5.5.5 `
    -o365_user 'admin@mydomain-on-o365.com' `
    -o365_password TheO365Password `
    -ma_notify_email 'notify@mydomain-on-o365.com'

```

The end result will be a master ready with a working UI interface (login as **cloud\cloudadmin**), ready to be configured with Locations, Jobs, etc.  


The Netmail search site will also be created at the Remote Provider Node.  In order for the new site to start working, a manual service restart is needed at the Remote Provider service.  It might affect the existing working sites, this is why it is not restarted automatically with this script.
