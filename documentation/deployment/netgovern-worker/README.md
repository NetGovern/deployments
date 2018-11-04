# Netgovern Archive Worker configuration

The starting point is after having deployed in your infrastructure a Netgovern Archive image.  
*If the VM is deployed using Azure ARM templates, this script runs automatically after deployment, using the parameters gathered by Azure.*

### Download the following scripts to the same location in the archive worker VM

* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/ConfigureWorker.ps1" target="_blank">ConfigureWorker.ps1</a>


### Example of parameters used to run the configuration wizard 
```
.\ConfigureWorker.ps1 -master_server_address 1.1.1.1 -master_admin_user administrator -master_admin_password ThePassword `
```