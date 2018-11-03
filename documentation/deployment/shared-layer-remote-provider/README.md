# Netgovern Remote Provider Configuration

The starting point is after having deployed in your infrastructure a Netgovern Archive image.  
*If the VM is deployed using Azure ARM templates, this script runs automatically after deployment, using the parameters gathered by Azure.*

### Download the following scripts to the same location in the archive worker VM

* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/NewRemoteProvider.ps1" target="_blank">NewRemoteProvider.ps1</a>


### Example of parameters used to run the configuration script to deploy an empty Remote Provider 
```
.\NewRemoteProvider.ps1 -ldap_server 1.1.1.1 -multitennipe_password 'AnotherPassword' -zookeeper_url '2.2.2.2:31000' `
```