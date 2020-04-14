# ConfigureCrawler.ps1
This script configures a node as a crawler node for a multitenant master

It should run from an deployed Archive VM, it needs to be able to access the Master Administrative share C$.
It also needs to access the Administrative shared C$ at the Remote Provider Server

As a prerequisite, the common functions ngfunctions.ps1 should be copied in the same folder from where this script is run.

## EXAMPLE
```
.\ConfigureCrawler.ps1 -master_server_address 1.1.1.1 -master_admin_user administrator `
    -master_admin_password ThePassword -netmail_user_password AnotherPassword `
    -postgres_password PostgresPassword `
    -rp_server_address 1.1.1.2 -rp_admin_user administrator -rp_admin_password AnotherOne
```