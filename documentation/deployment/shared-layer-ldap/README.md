# Netgovern Shared Layer configuration - ldap

The starting point is after having deployed in your infrastructure 2 linux ldap images from netmail.  
*If the VM is deployed using Azure ARM templates, this script runs automatically after deployment, using the parameters gathered by Azure.*

### Download the following script to the same location in the first VM that will create your ldap cluster

<a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/configure_ldap.sh" target="_blank">configure_ldap.sh</a>



### Example of parameters used to run the configuration wizard 
*The VM provided can be created by installing the PLATFORM rpm and creating a netmail user with rights to sudo without passwd*

The following shows how to configure the ldap cluster.  
The script has to be executed at each VM.  Each time pointing to the other mirror.
In our example, VM1 is 1.1.1.1 and VM2 is 1.1.1.2

From VM1
```
./install_ldap_cluster.sh -r 'Password' -c 'Password' -n 'Password' -i 1.1.1.2 
```

From VM2
```
./install_ldap_cluster.sh -r 'Password' -c 'Password' -n 'Password' -i 1.1.1.1 
```
