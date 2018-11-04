# ARM Template - LDAP cluster

This template deploys a new ldap cluster (2 Centos VMs) into an existing Azure Resource group.

The parameters feed the shell script that configures the ldap cluster as needed by netgovern cloud.

---

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fbitbucket.netmail.com%2Fprojects%2FPUB%2Frepos%2Fdeployments%2Fraw%2Fazure%2Fnetgovern-pod%2Fnetgovern-ldap-cluster%2Fazuredeploy.json" target="_blank">
    <img src="https://azuredeploy.net/deploybutton.png"/>
</a>

---

## Powershell:

```  
New-AzureRmResourceGroupDeployment -Name <deployment-name> -ResourceGroupName <resource-group-name> `
    -TemplateUri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/netgovern-pod/netgovern-ldap-cluster/azuredeploy.json
```

---

## Azure CLI:
```  
azure config mode arm
azure group deployment create <my-resource-group> <my-deployment-name> --template-uri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/netgovern-pod/netgovern-ldap-cluster/azuredeploy.json
```
