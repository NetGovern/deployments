# Netgovern Shared Layer configuration - ldap

The starting point is after having deployed in your infrastructure 2 linux ldap images from netmail.  
*If the VM is deployed using Azure ARM templates, this script runs automatically after deployment, using the parameters gathered by Azure.*

### Download the following script to the same location in the first VM that will create your ldap cluster

* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/install_ldap_cluster.sh.sh" target="_blank">install_ldap_cluster.sh</a>
* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/ldap_cloudadmin.ldif" target="_blank">ldap_cloudadmin.ldif</a>
* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/ldap_nipe_user.ldif" target="_blank">ldap_nipe_user.ldif</a>
* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/netmail.schema.ldif" target="_blank">netmail.schema.ldif</a>
* <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/slapd-access.conf" target="_blank">slapd-access.conf</a>


### Example of parameters used to run the configuration wizard 
*The VM provided can be created by installing the PLATFORM rpm and creating a netmail user with rights to sudo without passwd*

The following shows how to configure the ldap cluster.  The second node's IP address is 2.2.2.2
```
./install_ldap_cluster.sh -r 'Password' -c 'Password' -n 'Password' -i 2.2.2.2 -u netmail -p 'password' 

```
