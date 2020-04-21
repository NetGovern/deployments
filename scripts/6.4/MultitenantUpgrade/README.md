# Multitenant POD upgrade script

This script has to be run from the Remote Provider server.
It also needs the credentials for all the Windows and Linux servers (Archive and index).

This script has 2 parts:  

* Discovery
* Upgrade

## Discovery

It generates a json file with a map of the nodes (Remote Provider, Ldap, Index, Archive and Workers)

## Upgrade

It upgrades the nodes that meet the conditions (current version < target upgrade version).
It starts with Index, followed by the Remote Provider and Archive/Workers later.

It will leave the json file with the discovered nodes in a file within the same folder where the script is run from.

## Parameters

```powershell
It needs windows and linux admin passwords for the nodes as well as the target version to which upgrade

Most of the parameters names are self explanatory.  Some clarification below:

The option "unattended" will skip prompting the user to continue after displaying the discovered nodes in the pod.
The option "-upgradeIndex $false" will skip index upgrade
The option "-upgradeLdap $false" will skip ldap upgrade
The option "-upgradeRP $false" will skip the Remote Provider upgrade
The option "-upgradeArchive $false" will skip master/worker nodes upgrade.
The option "-skip_wrong_creds" will continue with the upgrade even if some of the nodes' credentials are not correct.
The option "-test_connectiviy" will discover all the nodes and test the credentials.
The option "-rpm_debug" will search for _debug packages (only applicable to RPMs)
The parameter "-manifest_url" is used to provide the manifest URL used by PLUS
```

## Examples

```powershell
The following launches a full upgrade to all the pod:
.\UpgradePod.ps1 -windows_admin_user "Administrator" -windows_admin_password "ThePassword" `
    -linux_admin_user netmail -linux_admin_password "ThePassword" -upgrade_version "6.3.0.1454" `
    -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword" `
    -manifest_url "http://plus-server/uuid"

Same as above but it will prompt for passwords:
.\UpgradePod.ps1 -upgrade_version "6.3.0.1454"

The following options will upgrade only the Remote Provider server:
.\UpgradePod.ps1 -upgradeIndex $false -upgradeArchive $false -upgradeLdap $false -upgrade_version "6.3.0.1454"

The below will only test for connectivity (it tries to log in to each discovered node):
.\UpgradePod.ps1 -test_connectivity -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword"

```

## Special note about LDAP schema upgrade
This script does not cover any schema upgrade to LDAP if the node has not been installed using NetGovern rpms. They will need to be handled manually if needed.

In order to upgrade the ldap schema:

Get the newest schema from the platform rpm,  by installing it in a disposable server or container and copying it:  /opt/ma/netmail/etc/netmail.schema.ldif  

Verify the location of the schema by looking at the service configuration. See the following example:

```bash
 cat /etc/openldap/slapd.conf
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/netmail.schema.ldif
```

Stop the ldap service
Make a backup of the old netmail.schema.ldif file
Replace the new schema file with the one provided from the rpm
Start the ldap service
