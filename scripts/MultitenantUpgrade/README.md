# Multitenant POD upgrade script
  
This script has to be run from the Remote Provider server.
It also needs the credentials for all the Windows and Linux servers (Archive and index).

This script has 2 parts:  
* Discovery
* Upgrade

## Discovery
It generates a json file with a map of the nodes (Remote Provider, Index, Archive and Workers)

## Upgrade
It upgrades the nodes that meet the conditions (current version < target upgrade version).
It starts with Index, followed by the Remote Provider and Archive/Workers later.

It will leave the json file with the discovered nodes in a file within the same folder where the script is run from.

## Parameters

```
<#

.SYNOPSIS
This script discovers the nodes in a multitenant environment and upgrades them after confirmation.

.DESCRIPTION
It needs windows and linux admin passwords for the nodes as well as the target version to which upgrade

Most of the parameters names are self explanatory.  
The option "interactive" will prompt the user to continue after displaying the discovered nodes in the pod.
The option "discoverOnly" will not run any upgrade but it will leave a json file called my-cluster-info.json in the same folder of the script location.

.EXAMPLE
.\DiscoveryAndUpgrade.ps1 -windows_admin_user "Administrator" -windows_admin_password "ThePassword" `
    -linux_admin_user netmail -linux_admin_password "ThePassword" -upgrade_version "6.3.0.1454" `
    -interactive -discoverOnly

#>
```

## About LDAP and Postgres
This script does not cover any schema upgrade to LDAP nor Postgres.
They will need to be handled manually if needed.

In order to upgrade the netmail schema:

1.  Download the newest schema from the following location: [netmail.schema.ldif](https://netgovernpkgs.blob.core.windows.net/download/netmail.schema.ldif)
2. Verify the location of the schema by looking at the service configuration.  See the following example:
```
 cat /etc/openldap/slapd.conf
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/netmail.schema.ldif
```
3. Stop the ldap service
4. Make a backup of the old netmail.schema.ldif file
5. Replace the new schema file with the one provided at the step 1
6. Start the ldap service