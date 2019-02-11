# NetGovern Pod deployment - Azure Marketplace
How to deploy a Pod using a NetGovern solution template

## Azure Marketplace

1. Go to [Azure Marketplace URL](https://azuremarketplace.microsoft.com)
![alt text](./imgs/1-azure_marketplace.png "Azure Search")  

2. Search for NetGovern in the search bar and select the MultiTenant Solution:
![alt text](./imgs/2-azure_marketplace.png "Azure Search Results")  

3. Click on "Get it Now"
![alt text](./imgs/3-azure_marketplace.png "Azure Solution Template")  

4. Fill in the required contact info:
![alt text](./imgs/4-azure_marketplace.png "Contact Info")  

5. You will be directed to Microsoft's Azure Portal.  Click on Create:
![alt text](./imgs/5-azure_portal.png "Create")  

6. The first step is to configure basic settings:  
    * An admin account and password that will be used for all of the VMs deployed within this solution template
    * The Azure subscription to be used
    * A new or empty resource group
    * The location
    ![alt text](./imgs/6-azure_portal.png "Basics")  

7. In the second step, the network has to be defined.  It can be an existing network or you can create a new one:
![alt text](./imgs/7-azure_portal.png "Network")  

8. Step 3 is used to define the VM sizes and the OS disk type chosen for each of the shared layer VMs that will be part of the pod:
![alt text](./imgs/8-azure_portal.png "VM Settings - Shared")  
![alt text](./imgs/9-azure_portal.png "VM Settings - VM Size")  
![alt text](./imgs/10-azure_portal.png "VM Settings - Shared 2")  

9. In the next step, the first tenant Master server settings have to be entered:
![alt text](./imgs/11-azure_portal.png "VM Settings - Master")  

10. Step 5 is to validate the settings entered before:
![alt text](./imgs/12-azure_portal.png "Summary")  

11. And we finally click on "Create":
![alt text](./imgs/13-azure_portal.png "VM Settings - Master")  

12. A Template Deployment will be launched, which can be followed from the same portal session:
![alt text](./imgs/14-azure_portal.png "Template Deployment Status 1")
![alt text](./imgs/15-azure_portal.png "Template Deployment Status 2")
![alt text](./imgs/16-azure_portal.png "Template Deployment Status 3")
![alt text](./imgs/14-azure_portal.png "Template Deployment Status 1")  

13. NetGovern Pod ready to use!
![alt text](./imgs/15-azure_portal.png "Virtual Machines")