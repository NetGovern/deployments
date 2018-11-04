# ARM Template - POD Deployment
This ARM template deploys the shared layer services needed for a multitenant installation.

The template collects parameters taht will be passed to each one of the nested templates in the subfolders.
The linked templates can be deployed separately if needed, by browsing to each subfolder.

---

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fbitbucket.netmail.com%2Fprojects%2FPUB%2Frepos%2Fdeployments%2Fraw%2Fazure%2Fnetgovern-pod%2Fazuredeploy.json" target="_blank">
    <img src="https://azuredeploy.net/deploybutton.png"/>
</a>

---

## Powershell:

```  
New-AzureRmResourceGroupDeployment -Name <deployment-name> -ResourceGroupName <resource-group-name> `
    -TemplateUri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/netgovern-pod/azuredeploy.json
```

---

## Azure CLI:
```  
azure config mode arm
azure group deployment create <my-resource-group> <my-deployment-name> --template-uri https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/azure/netgovern-pod/azuredeploy.json
```