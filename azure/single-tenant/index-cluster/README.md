# ARM Template - Index cluster

This template deploys the VMs to create a new index cluster (or only 1 VM, as indicated in the parameters) into an existing Azure Resource group.

---

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fbitbucket.netmail.com%2Fprojects%2FPUB%2Frepos%2Fdeployments%2Fraw%2Fazure%2Fsingle-tenant%2Findex-cluster%2Fazuredeploy.json" target="_blank">
    <img src="https://azuredeploy.net/deploybutton.png"/>
</a>

---

## Powershell:

```  
New-AzureRmResourceGroupDeployment -Name <deployment-name> -ResourceGroupName <resource-group-name> `
    -TemplateUri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/single-tenant/index-cluster/azuredeploy.json
```

---

## Azure CLI:
```  
azure config mode arm
azure group deployment create <my-resource-group> <my-deployment-name> --template-uri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/single-tenant/index-cluster/azuredeploy.json
```
