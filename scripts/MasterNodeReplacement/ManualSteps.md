# Single Node Master Replacement

## Pre requisite configuration.

All Windows nodes need to be able to accept PS Remote sessions.  Run the following powershell commands at each node:

```powershell
Enable-PSRemoting
& cmd /C "winrm quickconfig -force"
$certThumbprint = (New-SelfSignedCertificate -DnsName winrmCert -CertStoreLocation Cert:\LocalMachine\My).Thumbprint
& cmd /C "winrm create winrm/config/Listener?Address=*+Transport=HTTPS @{Hostname=`"winrmCert`"; CertificateThumbprint=`"$certThumbprint`"}"

New-NetFirewallRule -DisplayName "WinRM HTTPS" -Name "WinRM HTTPS" -Profile Any -LocalPort 5986 -Protocol TCP
New-NetFirewallRule -DisplayName "WinRM HTTP" -Name "WinRM HTTP" -Profile Any -LocalPort 5985 -Protocol TCP
```

## Upgrade the cluster to the latest version

All of the nodes need to be upgraded and the cluster has to be in good shape.  All nodes should be healthy.

---

## Join a Worker node using the setup wizard

Join a basic worker node (without extra services like crawler or remote provider)

---

## Postgresql

A Backup from the soon to be retired master is needed.  Run the following command, entering the postgres admin password when prompted:

```dos
C:\Program Files (x86)\PostgreSQL\9.3\bin> .\pg_dump.exe -d netmailarchive -U postgres -f c:\users\administrator\desktop\netmailarchive.dump
Password:
```

Go to the node that will become the master, copy the dump file taken in the previous step and run the following:

```dos
psql -U postgres -W -c "CREATE DATABASE netmailarchive"
```

```dos
psql -U postgres -W -d netmailarchive -f <path to dump file>
```

Change the connection string in ldap:
cn=GWOpenNode,cn=archiving,o=netmail  
The attribute "maLogCnnString" should be updated with the new IP address.

Each one of the crawler nodes'config will need to be updated as well.  Change the datasource sectionin the config file:

```dos
"C:\Program Files (x86)\Messaging Architects\Crawler\apache-tomcat-7.0.40\webapps\unifyle\WEB-INF\classes\instanceContext.xml"
```

```xml
<bean id="dataSource"
          class="org.springframework.jdbc.datasource.DriverManagerDataSource">
        <property name="driverClassName" value="org.postgresql.Driver" />
        <property name="url" value="jdbc:postgresql://<oldIP>:5432/netmailarchive" />
        <property name="username" value="postgres" />
        <property name="password" value="AdminPassword" />
    </bean>
```

---

## OpenLDAP

DELETE the Worker object attributes from ldap:

```ldif
dn: cn=<HOST_NAME>,cn=system,o=netmail
dn: cn=Worker node (<IP_ADDRESS>),cn=Nodes,cn=GWOpenNode,cn=archiving,o=netmail
```

In the soon to be Master node do the following:  
Copy 05-openldap.conf from "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\launcher.d-available" to "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\launcher.d"
Restart platform services

Run:

```dos
cd "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\scripts\setup"
ConfigureOpenLDAP.bat <netmail password> join
```

```dos
cd "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\scripts\setup"
ConfigureMMOpenLDAP.bat <your own ip address> <ip address of a node containing a ldap replica>
```

Remove the old master server from the CFS cluster
Run the following command:

```dos
C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\sbin\cfs.exe cabandon <old master IP address>
```

Note: If the cfs command does not work, you'll need to manually remove the entry from all of the nodes' cfs.json file (index servers as well)

Stop platform on all nodes.  
On the worker node that contains the ldap replica: Replace the old master's IP address with the new one by editing the file "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\slapd-multimaster.conf"

In all Windows nodes  
Replace the old IP address with the new one in "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\mdb.conf".

---

## Archive Configuration

Copy C:\Program Files (x86)\Messaging Architects\Config\ClusterConfig.xml from the original master to the new one.  Change the IP address accordingly.  Update also the new ldap connection string, modify the line that starts with:

```xml
<PRMS><![CDATA[<PRMS><CONNECTION DN="cn=netmail,cn=system,o=netmail" IP="OLD_IP"
```

Modify the remaining worker nodes' ClusterConfig.xml, removing the Node tag referring to the worker node that is being promoted to Master:

```xml
<Node>
<Type>Worker</Type>
<NodeID>IP ADDRESS</NodeID>
...
...
</Node>
```

Also, change the IP address within the Node tag of the Master to reflect the changes:

```xml
<Node>
      <Type>MasterAndWorker</Type>
      <NodeID>OLD_IP</NodeID>
      <URL>http://OLD_IP:8585</URL>
...
...
</Node>
```

Run the following batch script on the new Master:

```dos
C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\scripts\setup\Win-DesignateMaster.bat
```

---

## Remote Provider

If the Remote Provider will be hosted in the new master, run the following powershell scripts on the new Master.

Enable the service:

```powershell
$rpServiceConfPath = "$env:NETMAIL_BASE_DIR\etc\launcher.d\60-awa.conf"
Set-Content -Value "group set `"NetGovern Client Access`" `"Provides support for client access to NetGovern`"" `
    -Path $rpServiceConfPath
Add-Content -Value "start -name awa `"$env:NETMAIL_BASE_DIR\..\RemoteProvider\XAWAService.exe`"" `
    -Path $rpServiceConfPath
```

Configures platform info

```powershell
$json = Get-Content $env:NETMAIL_BASE_DIR\var\docroot\info\netmail-remote-provider
$objFromJson = $json | ConvertFrom-Json
$objFromJson | add-member -Name "configured" -value ($true) -MemberType NoteProperty
$objFromJson | ConvertTo-Json | Out-File $env:NETMAIL_BASE_DIR\var\docroot\info\netmail-remote-provider -Encoding ascii
Get-Content $env:NETMAIL_BASE_DIR\var\docroot\info\netmail-remote-provider
```

The output should show something like:

```json
 {
    "version":  "6.4.0.1151",
    "previousVersions":  [

                         ],
    "configured":  true
}
```

And copy the configuration files from the old Master to the new Master Remote Provider folder:

```dos
C:\Program Files (x86)\Messaging Architects\RemoteProvider\xgwxmlv.cfg
C:\Program Files (x86)\Messaging Architects\RemoteProvider\jetty-ssl.xml
C:\Program Files (x86)\Messaging Architects\RemoteProvider\WebContent\config.xml
```
