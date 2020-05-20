<#

.SYNOPSIS
This script replaces an existing Archive Master in a multi tenant architecture

.DESCRIPTION
The windows administrator credentials should be the same across Master and worker Nodes as well as the Remote Provider server.
The parameter tenantId is used to identify the correct RemoteProvider folder

.EXAMPLE
.\MultiTenantReplaceMaster.ps1 `
    -windowsAdminUser Administrator `
    -windowsAdminPassword 'The Password' `
    -oldMaster 2.2.2.2 `
    -remoteProvider 3.3.3.3 `
    -tenantId tenant01
#>

Param(
    [Parameter(Mandatory)]
    [string]$oldMaster,
    [Parameter(Mandatory)]
    [string]$windowsAdminUser,
    [Parameter(Mandatory)]
    [string]$windowsAdminPassword,
    [Parameter(Mandatory)]
    [string]$remoteProvider,
    [Parameter(Mandatory)]
    [string]$tenantId
)

Set-Location $PSScriptRoot

#Source functions and config templates
. .\myFunctions.ps1

$date = Get-Date -f yyyyMMdd_hh_mm_ss
$logfile = ".\$date`_MasterSetupWizard_log.txt"
Write-Log "`r`nMaster Node replacement Script Started" $logfile -toStdOut
Write-Log "---------------------------------------" $logfile -toStdOut
Write-Log "`r`nWarning:" $logfile -toStdOut
Write-Log "------------" $logfile -toStdOut
Write-Log "`r`nIf the new Master's IP address is in a different subnet than the old Master to be migrated:" $logfile -toStdOut
Write-Log "`r`nPlease make sure that the postgres server is configured to accept connections from the new subnet" $logfile -toStdOut
Write-Log "`r`nin the configuration file: /var/lib/pgsql/data/pg_hba.conf" $logfile -toStdOut
Write-Output "`r`n"

# Setting up self generated variables
$newMaster = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address

#Map oldMaster C$
$windowsAdminPasswordSecureString = $windowsAdminPassword | ConvertTo-SecureString -AsPlainText -Force
$windowsAdminCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windowsAdminUser, $windowsAdminPasswordSecureString
Write-Output "Mapping oldMaster $oldMaster\c$\Program Files (x86)\Messaging Architects"
Try {
    New-PSDrive -name "oldMaster" -PSProvider FileSystem `
        -Root "\\$oldMaster\c$\Program Files (x86)\Messaging Architects" `
        -Credential $windowsAdminCredentials
}
catch {
    Throw "Cannot map \\$oldMaster\c$\Program Files (x86)\Messaging Architects as user: $windowsAdminUser"
    Exit 1
}
Write-Output "oldMaster: mapped successfully"

#Configure edir.properties
Write-Log "`r`nCopy edir.properties" $logfile -toStdOut
Copy-Item "oldMaster:\Nipe\Config\edir.properties" -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config" -Force

Write-Log "`r`nCopy eclients" $logfile -toStdOut
Copy-Item "oldMaster:\Netmail WebAdmin\var\dbf\eclients.dat" -Destination "$env:NETMAIL_BASE_DIR\var\dbf" -Force

Write-Log "`r`nCopy apikey" $logfile -toStdOut
Copy-Item "oldMaster:\Netmail WebAdmin\var\dbf\apikey.dat" -Destination "$env:NETMAIL_BASE_DIR\var\dbf" -Force

# Parse ldap info
$edirProperties = Get-Content "$env:NETMAIL_BASE_DIR\..\Nipe\Config\edir.properties"
$ldapServer = (($edirProperties | Select-String 'edir.host=').Line -split '=', 2)[1]
$ldapLoginDn = (($edirProperties | Select-String 'edir.logindn=').Line -split '=', 2)[1]
$ldapLoginPassword = (($edirProperties | Select-String 'edir.loginpwdclear=').Line -split '=', 2)[1]
$ldapBaseDn = (($edirProperties | Select-String 'edir.container=').Line -split 'archiving,', 2)[1]

# Test ldap connectivity
Write-Output "Verify ldap connectivity to $ldapServer as $ldapLoginDn"
$ldapConn = TestLDAPConn -ldapServer $ldapServer -ldapAdminDn $ldapLoginDn -ldapAdminPassword $ldapLoginPassword
if ($ldapConn -eq 0) {
    Write-Output "Success`r`n"
} else {
    Throw "Cannot connect to ldap (port 389).  Cannot continue"
    Exit 1
}

$ldapConnection = createLdapConnection -ldapServer $ldapServer -ldapAdminDn $ldapLoginDn -ldapAdminPassword $ldapLoginPassword
Write-Log "Recreate Master Object in LDAP" $logfile -toStdOut
Write-Log "cn=Default Master($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,$ldapBaseDn" $logfile -toStdOut

addLdapDn -ldapConnection $ldapConnection `
    -dnToAdd "cn=Default Master($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,$ldapBaseDn" `
    -objectClass "maGWClusterNode"

modifyLdapDn -ldapConnection $ldapConnection `
    -dnToModify "cn=Default Master($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,$ldapBaseDn" `
    -attributeName "maId" -newValue $newMaster -modType "Add"

modifyLdapDn -ldapConnection $ldapConnection `
    -dnToModify "cn=Default Master($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,$ldapBaseDn" `
    -attributeName "description" -newValue "Master Node" -modType "Add"

deleteLdapDn -ldapConnection $ldapConnection `
    -dnToDelete "cn=Default Master($oldMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,$ldapBaseDn"

Write-Log "`r`nCreate nodeid.cfg" $logfile -toStdOut
Set-Content -Value $newMaster -Path ".\nodeid.cfg"
Copy-Item ".\nodeid.cfg" -Destination "$env:NETMAIL_BASE_DIR\..\Config" -Force

#Copy and Update ClusterConfig.xml
Write-Log "`r`Update ClusterConfig.xml with newMaster IP Address" $logfile -toStdOut
$clusterConfigXml = Get-content -Path "oldMaster:\Config\ClusterConfig.xml"
$clusterConfigXml.Replace($oldMaster, $newMaster) | Out-File `
    -FilePath "$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml" -Encoding ascii

#Copy mdb.conf
Write-Log "`r`nCopy mdb.conf" $logfile -toStdOut
Copy-Item "oldMaster:\Netmail Webadmin\etc\mdb.conf" -Destination "$env:NETMAIL_BASE_DIR\etc" -Force

#Copy nipe properties
Write-Log "`r`nCopy nipe properties" $logfile -toStdOut
Copy-Item "oldMaster:\Nipe\Config\solr.properties" -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config" -Force
Copy-Item "oldMaster:\Nipe\Config\nipeSearcher.properties" -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config" -Force
Copy-Item "oldMaster:\Nipe\Config\netmail.properties" -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config" -Force

#Copy RemoteProvider for Export jobs
Write-Log "`r`nCopy apikey" $logfile -toStdOut
Copy-Item "oldMaster:\RemoteProvider\xgwxmlv.cfg" -Destination "$env:NETMAIL_BASE_DIR\..\RemoteProvider\xgwxmlv.cfg" -Force



# Copy conf files
Write-Log "`r`nCopy launcher.d\*.conf" $logfile -toStdOut
Copy-Item "oldMaster:\Netmail Webadmin\etc\launcher.d\*.conf" `
    -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force

#Configure "netmail-openldap" info doc snippet
Write-Log "`r`nCreate netmail-openldap info doc snippet" $logfile -toStdOut
$netmailOpenldapPath = "$env:NETMAIL_BASE_DIR\var\docroot\info\netmail-openldap"
$ldapBaseDnEncoded = $ldapBaseDn.Replace("=","%3D")
Set-Content -Value "{" -Path $netmailOpenldapPath
Add-Content -Value "    `"uri`": `"ldap://$ldapServer`:389/o=netmail?machine=$env:COMPUTERNAME&basedn=$ldapBaseDnEncoded`"" `
    -Path $netmailOpenldapPath
Add-Content -Value "}" -Path $netmailOpenldapPath

#Configure "netmail-archive" info doc snippet
Write-Log "`r`nCreate netmail-archive info doc snippet" $logfile -toStdOut
$netmailArchive = Get-Content "$env:NETMAIL_BASE_DIR\etc\info.json" | Out-String | `
    ConvertFrom-Json | Select-Object -ExpandProperty "netmail-archive"
$netmailArchive | Add-Member -Name "master" -Value "true" -MemberType NoteProperty
$netmailArchive | ConvertTo-Json -Compress | Set-Content -Path "$env:NETMAIL_BASE_DIR\var\docroot\info\netmail-archive"

# Copy ajaj.json
Copy-Item "oldMaster:\Netmail Webadmin\var\docroot\info\ajaj.json" `
    -Destination "$env:NETMAIL_BASE_DIR\var\docroot\info" -Force

# Create New CFS Cluster
Write-Log "`r`nCreate New CFS Cluster" $logfile -toStdOut
Write-Log "----------------------" $logfile -toStdOut
$cfsOutput = & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-ConfigureCFS.bat new $newMaster | Out-String
Write-Log $cfsOutput $logfile 
if ($?) {
    Write-Log "Success" $logfile -toStdOut
} else {
    Write-Log "Create New CFS Cluster failed.  More info in $logfile" $logfile -toStdOut
}

# Generate ssl certificates for apid
Write-Log "`r`nCreate ssl certificates for apid" $logfile -toStdOut
$newCertsDirOutput = New-Item -ItemType Directory -Force -Path "$env:NETMAIL_BASE_DIR\var\openldap\certs" | Out-String
Write-Log $newCertsDirOutput $logfile
Set-Content -Value "These certificates are needed for APID to start.  They have to be named openldap.* but it's not related to the actual ldap server"`
    -Path "$env:NETMAIL_BASE_DIR\var\openldap\certs\readme.txt"
$env:OPENSSL_CONF = "$env:NETMAIL_BASE_DIR\etc\openssl.cnf"
$outputOpenssl = & $env:NETMAIL_BASE_DIR\sbin\openssl.exe req -newkey rsa:2048 -x509 -nodes `
    -out "$env:NETMAIL_BASE_DIR\var\openldap\certs\openldap.crt" `
    -keyout "$env:NETMAIL_BASE_DIR\var\openldap\certs\openldap.key" `
    -days 3650 -subj "/CN=${newMaster}/O=netmail/C=CA" `
    -config "$env:NETMAIL_BASE_DIR\etc\openssl.cnf"  2>&1 | Out-String 

Write-Log $outputOpenssl $logfile

Write-Log "`r`nAllow Local subnet traffic" $logfile -toStdOut
# Allow Local Subnet
$output_firewall_rule = New-NetFirewallRule `
    -DisplayName "NetGovern_Allow_Local_Subnet" `
    -Direction Inbound `
    -Profile 'Domain', 'Private', 'Public' `
    -Action Allow `
    -RemoteAddress LocalSubnet | Out-String
Write-Log $output_firewall_rule $logfile

Write-Log "`r`nReconfigure unused services" $logfile -toStdOut
$postgres_disable_output = & sc.exe config "postgresql-9.3" start=demand | Out-String
Write-Log $postgres_disable_output $logfile -toStdOut

#Restart NetGovern services
Write-Log "Restarting NetGovern Launcher Service" $logfile -toStdOut
Restart-Service -Name NetmailLauncherService

# Update Worker nodes
[xml]$clusterConfig = Get-Content $env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml
$nodesList = ($clusterConfig.GWOpenConfig.Nodes.Node | Where-Object {
        $_.Type -eq "Worker"
    }).NodeID

.\UpdateArchiveCluster.ps1 `
    -windowsAdminUser $windowsAdminUser `
    -windowsAdminPassword $windowsAdminPassword `
    -oldMaster $oldMaster `
    -newMaster $newMaster `
    -nodesList ($nodesList -join ',')

# Update RP
Write-Output "Mapping oldMaster $remoteProvider\c$\Program Files (x86)\Messaging Architects"
Try {
    New-PSDrive -name "remoteProvider" -PSProvider FileSystem `
        -Root "\\$remoteProvider\c$\Program Files (x86)\Messaging Architects" `
        -Credential $windowsAdminCredentials
}
catch {
    Throw "Cannot map \\$remoteProvider\c$\Program Files (x86)\Messaging Architects as user: $windowsAdminUser"
    Exit 1
}
Write-Output "remoteProvider: mapped successfully"

$xgwxmlvCfg = Get-content -Path "remoteProvider:\RemoteProvider_$tenantId\xgwxmlv.cfg"
$xgwxmlvCfg.Replace($oldMaster, $newMaster) | Out-File `
    -FilePath "remoteProvider:\RemoteProvider_$tenantId\xgwxmlv.cfg" -Encoding ascii

# TODO: Connect to RP and restart the remote provider process via launcher


