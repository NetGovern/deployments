# Netgovern Archive Master configuration

The starting point is after having deployed in your infrastructure a Netgovern Archive image.  
*If the VM is deployed using Azure ARM templates, this script runs automatically after deployment, using the parameters gathered by Azure.*

### Download the following scripts to the same location in the archive master VM

* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/MasterSetupWizard.ps1" target="_blank">MasterSetupWizard.ps1</a>
* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/basedata.ps1" target="_blank">basedata.ps1</a>
* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/ConfigureDP.ps1" target="_blank">ConfigureDP.ps1</a>
* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/ngfunctions.ps1" target="_blank">ngfunctions.ps1</a>


### Example of parameters used to run the configuration wizard 
```
.\MasterSetupWizard.ps1 -ldap_server 1.1.1.1 `
    -ldap_admin_dn 'cn=netmail,cn=system,o=netmail' `
    -ldap_admin_password 'TheLdapPassword' `
    -zookeeper_url 2.2.2.2:31000 `
    -postgresql_server 3.3.3.3 `
    -postgresql_port 5432 `
    -postgresql_admin_user postgres `
    -postgresql_admin_password 'ThePostgresPassword' `
    -tenant_id tenant_test `
    -netmail_password 'TheNetmailPassword' `
    -o365_user 'admin@mydomain-on-o365.com' `
    -o365_password 'TheO365Password' `
    -o365_url 'https://outlook.office365.com/PowerShell' `
    -ma_notify_email 'notify@mydomain-on-o365.com' `
    -remote_provider_ip_address 4.4.4.4
    -remote_provider_admin_user 'administrator'
    -remote_provider_password 'TheRemoteProviderPassword'

```