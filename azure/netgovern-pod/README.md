# ARM Templates

## Azure Resource Management templates
The provided set of templates enable the partner or client to provision netgovern VMs and infrastructure.

* netgovern-pod/* contains a main arm template that links to all of the subfolders.  Each linked template can also be deployed individually.
* netgovern-master/* contains the arm template to deploy and configure a new master into an existing pod
* netgovern-worker/* contains the arm template to deploy and configure a new worker for an existing master
* infrastructure-network/* contains the arm template to deploy a new Virtual Network and Subnet