<#

.SYNOPSIS
This script configures an empty Remote Provider for a multitenant architecture

.DESCRIPTION
The script should run from an image with the pre-requisites and netmail installed

.EXAMPLE
.\NewRemoteProvider.ps1 -ldap_server 1.1.1.1 -multitennipe_password AnotherPassword -zookeeper_ip '2.2.2.2'

.NOTES
It outputs to console the http port for this DP that is configured in the shared Remote Provider server

#>

Param(
    [Parameter()]
    [string]$ldap_server,
    [Parameter()]
    [string]$multitennipe_password,
    [Parameter()]
    [string]$zookeeper_ip
)


"Dummy File" | Out-File "$env:NETMAIL_BASE_DIR\etc\mdb.conf" -encoding ascii
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

# Unix2Dos - Just in case
if ( Select-String -InputObject $edir_properties_for_nipe -Pattern "[^`r]`n" ) {
    $edir_properties_for_nipe = $edir_properties_for_nipe.Replace("`n", "`r`n")
}

$edir_properties_for_nipe | `
    Out-File -FilePath "C:\Program Files (x86)\Messaging Architects\Nipe\Config\edir.properties" -encoding ascii
"hosts=$($zookeeper_ip):32000/solr" | `
    Out-File -FilePath "C:\Program Files (x86)\Messaging Architects\Nipe\Config\solr.properties" -encoding ascii

$netmail_properties = Get-Content "C:\Program Files (x86)\Messaging Architects\Nipe\Config\netmail.properties"
$scheme = "scheme=file"
$resource = "resource=info.json"
$clusterscheme = "clusterscheme=none"
$netmail_properties = $netmail_properties.replace("scheme=https", "$scheme")
$netmail_properties = $netmail_properties.replace("resource=https://localhost/info.json", "$resource")
$netmail_properties = $netmail_properties.replace("clusterscheme=https", "$clusterscheme")
$netmail_properties += "`r`ntrustedIps=All" 

# Unix2Dos - Just in case
if ( Select-String -InputObject $netmail_properties -Pattern "[^`r]`n" ) {
    $netmail_properties = $netmail_properties.Replace("`n", "`r`n")
}
$netmail_properties | Out-File -FilePath "C:\Program Files (x86)\Messaging Architects\Nipe\Config\netmail.properties" -encoding ascii

# Allow SMB traffic
Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True

# Allow 50 Ports for Remote Provider (SSL and non SSL)
New-NetFirewallRule `
    -DisplayName "Netmail_Ports_RemoteProvider_8443-8495_and_8888-8940" `
    -Direction Inbound `
    -Profile 'Domain', 'Private', 'Public' `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 8443-8495, 8888-8940

Set-NetConnectionProfile -InterfaceAlias Ethernet -NetworkCategory Private
