# Netgovern Shared Database layer

## Postgres
We have 3 options to deploy the postgres server.
* It can be added as a separate VM, using the Azure ARM template.

* It can be installed and configured in any of the already deployed servers (ldap, shared storage).  *Installation and configuration scripts are provided only for CentOS 7.x*

* It can be deployed as an Azure service: Azure Database for Postgres.  *This option reduces maintenance as it handled by Azure*

To install and configure postgres on CentOS 7.x: 
Download: <a href="https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/install_postgres.sh" target="_blank">install_postgres.sh</a>  
  
Run it:
```
./install_postgres.sh -p <postgres password> -n <CIDR network to allow>
```

---

## MS SQL Database
***Coming soon***