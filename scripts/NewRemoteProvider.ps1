<#

.SYNOPSIS
This script configures an empty Remote Provider for a multitenant architecture

.DESCRIPTION
The script should run from an image with the pre-requisites and netmail installed

.EXAMPLE
.\NewRemoteProvider.ps1 -ldap_server 1.1.1.1 -multitennipe_password AnotherPassword -zookeeper_url '2.2.2.2:31000'

.NOTES
It outputs to console the http port for this DP that is configured in the shared Remote Provider server

#>

Param(
    [Parameter()]
    [string]$ldap_server,
    [Parameter()]
    [string]$multitennipe_password,
    [Parameter()]
    [string]$zookeeper_url
)


"Dummy File" | Out-File "$env:NETMAIL_BASE_DIR\etc\mdb.conf" -encoding utf8
Write-Output "Create Netmail Indexer launcher config file"
& $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureIndexer.bat
Remove-Item -Path "$env:NETMAIL_BASE_DIR\etc\mdb.conf" -Force

Write-Output "Configuring NIPE .properties files"
$edir_properties_for_nipe = @"
edir.host=$ldap_server
edir.port=389
edir.logindn=cn=multitennipe,o=netmail
edir.loginpwdclear=$multitennipe_password
edir.container=o=netmail
edir.ssl=false
edir.multitenant=true

"@

$edir_properties_for_nipe | `
    Out-File -FilePath "C:\Program Files (x86)\Messaging Architects\Nipe\Config\edir.properties" -encoding Utf8
"hosts=$zookeeper_url" | `
    Out-File -FilePath "C:\Program Files (x86)\Messaging Architects\Nipe\Config\solr.properties" -encoding Utf8

$netmail_properties = Get-Content "C:\Program Files (x86)\Messaging Architects\Nipe\Config\netmail.properties"
$scheme = "scheme=file"
$resource = "resource=info.json"
$clusterscheme = "clusterscheme=none"
$netmail_properties = $netmail_properties.replace("scheme=https", "$scheme")
$netmail_properties = $netmail_properties.replace("resource=https://localhost/info.json", "$resource")
$netmail_properties = $netmail_properties.replace("clusterscheme=https", "$clusterscheme")
$netmail_properties += "`ntrustedIps=All" 
$netmail_properties | Out-File -FilePath "C:\Program Files (x86)\Messaging Architects\Nipe\Config\netmail.properties" -encoding Utf8

# Allow SMB traffic
Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True