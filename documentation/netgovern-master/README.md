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
    -ldap_admin_password 'password' `
    -zookeeper_url '2.2.2.2:31000' `
    -postgresql_server 3.3.3.3 `
    -postgresql_port 5432 `
    -postgresql_admin_user postgres `
    -postgresql_admin_password 'password2' `
    -tenant_id tenant01 `
    -netmail_password 'password3' `
    -shared_storage_path '\\4.4.4.4\shared' `
    -shared_storage_account 'shared_user' `
    -shared_storage_password 'password4' `
    -exchange_server 5.5.5.5 `
    -exchange_user 'administrator@exchange.com' `
    -exchange_password 'password5' `
    -exchange_url 'https://5.5.5.5/Powershell' `
    -ma_notify_email 'notify@exchange.com' `
    -smtp_server 6.6.6.6 `
    -smtp_server_port '25' `
    -smtp_user_account '' `
    -smtp_user_password ''
```