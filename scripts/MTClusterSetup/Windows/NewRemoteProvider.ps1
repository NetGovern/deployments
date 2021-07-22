<#

.SYNOPSIS
This script configures an empty Remote Provider for a multitenant architecture

.DESCRIPTION
The script should run from an image with the pre-requisites and netmail installed. Must be run on dedicated RemoteProvider.

.EXAMPLE
.\NewRemoteProvider.ps1 -ldap_server 1.1.1.1 -multitennipe_password AnotherPassword -linux_admin_password AnotherPassword -linux_admin_user USER  -zookeeper_ip '2.2.2.2'

.NOTES
It outputs to console the http port for this DP that is configured in the shared Remote Provider server

#>

Param(
    [Parameter()]
    [string]$ldap_server,
    [Parameter()]
    [string]$multitennipe_password,
    [Parameter()]
    [string]$linux_admin_password,
    [Parameter()]
    [string]$linux_admin_user,
    [Parameter()]
    [string]$zookeeper_ip
)

Set-Location $PSScriptRoot
$kscpExe = "$PSScriptRoot\kscp.exe"
$klinkExe = "$PSScriptRoot\klink.exe"

"Dummy File" | Out-File "$env:NETMAIL_BASE_DIR\etc\mdb.conf" -encoding ascii
Write-Output "Create NetGovern Indexer launcher config file"
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

# Allow a pool of 50 Ports for Remote Provider (SSL and non SSL)
New-NetFirewallRule `
    -DisplayName "NetGovern_Ports_RemoteProvider_8443-8495_and_8888-8940" `
    -Direction Inbound `
    -Profile 'Domain', 'Private', 'Public' `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 8443-8495, 8888-8940

# Allow Local Subnet
New-NetFirewallRule `
    -DisplayName "NetGovern_Allow_Local_Subnet" `
    -Direction Inbound `
    -Profile 'Domain', 'Private', 'Public' `
    -Action Allow `
    -RemoteAddress LocalSubnet

function launchLinuxSchemaUpgrade {
    Param(
        [Parameter()]
        [string]$nodeIp
    )
    
    Copy-Item "$env:NETMAIL_BASE_DIR\etc\netmail.schema.ldif" -Destination "$PSScriptRoot/netmail.schema.ldif"
    $launcherScript += ""
    
  

    #LDAP schema update
    
    $launcherScript = "sudo cp /opt/ma/netmail/etc/netmail.schema.ldif /home/netmail/netmail.schema.ldif_old"
    $launcherScript += "`r`nsudo systemctl stop netmail"
    $launcherScript += "`r`nsudo cp /home/netmail/netmail.schema.ldif  /opt/ma/netmail/etc/netmail.schema.ldif"
    $launcherScript += "`r`nsudo systemctl start netmail"
    $launcherScript | Out-File -FilePath ".\$nodeIp-launchLDIFSchemaUpdate.sh" #to change . to $PSScriptRoot
            
    $kscpParameters = "-auto-store-sshkey", "-pw", `
        "${linux_admin_password}", "-l", "${linux_admin_user}", "$PSScriptRoot/netmail.schema.ldif"+" $nodeIp-launchLDIFSchemaUpdate.sh", "${nodeIp}:/home/$linux_admin_user/"
        $copyRpmsCommand = "${kscpExe} ${kscpParameters}"
    Write-Host "`r`Copying LDIF schema to $nodeIp"
            try {
                 Invoke-Expression $copyRpmsCommand
            }
            catch {
                Write-Host "`r`nCannot copy Update SCHEMA to $nodeIp. You can manually copy it on the LDAP nodes"
        Break
    }
    
 
    $klinkParameters = "-t", "-auto-store-sshkey", "-pw", `
            "${linux_admin_password}", "-l", "${linux_admin_user}", "${nodeIp}", `
            "sudo yum install -y dos2unix ""&&"" sudo dos2unix /home/$linux_admin_user/*.sh ""&&"" bash /home/$linux_admin_user/$nodeIp-launchLDIFSchemaUpdate.sh"
    $installRpmsCommand = "& `"${klinkExe}`" ${klinkParameters}"
    $installRpmsScriptBlock = [Scriptblock]::Create($installRpmsCommand)
    $outputFileName = "$nodeType-$($nodeIp)-$(Get-Date -f "MMddhhmmss").txt"


        try {
            Invoke-Command -ScriptBlock $installRpmsScriptBlock -ErrorAction Stop | Out-File $outputFileName
        }
        catch {
            Write-Host "`r`nCannot start schema upgrade at $nodeIp"
            Break
        }

    
    Write-Host "Schema Upgrade finished @ $nodeIp"
}

launchLinuxSchemaUpgrade -nodeIp $ldap_server
