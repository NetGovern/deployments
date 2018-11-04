# ARM Template - New Worker

This template deploys and adds a new Worker node into a multitenant mode Archive Master.
The ARM parameters will feed the Powershell configuration script that will run after the VM is deployed.

---

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fbitbucket.netmail.com%2Fprojects%2FPUB%2Frepos%2Fdeployments%2Fraw%2Fazure%2Fnetgovern-worker%2Fazuredeploy.json" target="_blank">
    <img src="https://azuredeploy.net/deploybutton.png"/>
</a>

---

## Powershell:

```  
New-AzureRmResourceGroupDeployment -Name <deployment-name> -ResourceGroupName <resource-group-name> `
    -TemplateUri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/netgovern-worker/azuredeploy.json
```

---

## Azure CLI:
```  
azure config mode arm
azure group deployment create <my-resource-group> <my-deployment-name> --template-uri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/netgovern-worker/azuredeploy.json
```
