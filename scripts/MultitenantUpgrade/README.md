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
It needs windows and linux admin passwords for the nodes as well as the target version to which upgrade

Most of the parameters names are self explanatory.  Some clarification below:

The option "unattended" will skip prompting the user to continue after displaying the discovered nodes in the pod.
The option "discover_only" will not run any upgrade but it will leave a json file called my-cluster-info.json in the same folder of the script location.
The option "no_index" will skip index upgrade
The option "no_master" will skip master/worker nodes upgrade.
The option "skip_wrong_creds" will continue with the upgrade even if some of the nodes' credentials are not correct.
The option "test_connectiviy" will discover all the nodes and test the credentials.
To upgrade only the Remote Provider server, -no_index and -no_master can be used.
```

## Examples
```
The following launches a full upgrade to all the pod:
.\UpgradePod.ps1 -windows_admin_user "Administrator" -windows_admin_password "ThePassword" `
    -linux_admin_user netmail -linux_admin_password "ThePassword" -upgrade_version "6.3.0.1454" `
    -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword"

Same as above but it will prompt for passwords:
.\UpgradePod.ps1 -upgrade_version "6.3.0.1454"

The following options will upgrade only the Remote Provider server:
.\UpgradePod.ps1 -no_index -no_master -upgrade_version "6.3.0.1454"

The below will only test for connectivity (it tries to log in to each discovered node):
.\UpgradePod.ps1 -test_connectivity -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword"

These options will discover the nodes in the pod:
.\UpgradePod.ps1 -discover_only -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword"

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