<#

.SYNOPSIS
This script adds a worker node to a multitenant node master

.DESCRIPTION
The script should run from an deployed Archive VM, it needs to be able to access the Master Administrative share C$.

.EXAMPLE
.\ConfigureWorker.ps1 -master_server_address 1.1.1.1 -master_admin_user administrator -master_admin_password ThePassword


#>

Param(
    [Parameter()]
    [string]$master_server_address,
    [Parameter()]
    [string]$master_admin_user,
    [Parameter()]
    [string]$master_admin_password,
    [Parameter()]
)

# Setting up self generated variables
$ipaddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address
$master_admin_secure_string_password = ConvertTo-SecureString $master_admin_password -AsPlainText -Force
$master_credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $master_admin_user, $master_admin_secure_string_password

#Map the drive
New-PSDrive -name "MASTER" -PSProvider FileSystem -Root "\\$master_server_address\c$\Program Files (x86)\Messaging Architects" -Credential $master_credentials

Write-Output "Stopping Service"
Stop-Service -Name NetmailLauncherService

Write-Output "Configuring Nipe Service"
Copy-Item -Path "$env:NETMAIL_BASE_DIR\..\ConfigTemplates\Nipe\netmail.properties" `
    -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config\"
Copy-Item -Path "MASTER:\Nipe\Config\edir.properties" `
    -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config\"
Copy-Item -Path "MASTER:\Nipe\Config\solr.properties" `
    -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config\"

#Create "50-indexer.conf"
$50_indexer_path = "$env:NETMAIL_BASE_DIR\etc\launcher.d\50-indexer.conf"
Set-Content -Value 'group set "Netmail Indexer" "Runs Netmail Indexing services"' `
    -Path $50_indexer_path
Add-Content -Value 'start -name indexer "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\..\Nipe\IndexerService.exe"' `
    -Path $50_indexer_path

Remove-PSDrive -Name MASTER

Write-Output "Configuring Open Thread Pool"
#Create "55-open.conf"
$55_open_path = "$env:NETMAIL_BASE_DIR\etc\launcher.d\55-open.conf"
Set-Content -Value 'group set "Netmail Archive" "Provides support for parallel processing of Netmail jobs"' `
    -Path $55_open_path
Add-Content -Value 'start -name archive "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\..\MAThreadPool.exe"' `
    -Path $55_open_path

# Create nodeid.cfg
Set-Content -Value $ipaddress -Path ".\nodeid.cfg"
Copy-Item ".\nodeid.cfg" -Destination "$env:NETMAIL_BASE_DIR\..\Config" -Force

# Create clusterConfig.xml
$clusterConfig_xml = Get-content -Path ("$env:NETMAIL_BASE_DIR\..\Config\clusterConfigWorker.xml")
$clusterConfig_xml = $clusterConfig_xml -replace '<MASTERIP/>', "$master_server_address"
$clusterConfig_xml = $clusterConfig_xml -replace '<MASTER_REMOTETCP/>', "8585"
$clusterConfig_xml = $clusterConfig_xml -replace '<NOPEIP/>', "$ipaddress"
$clusterConfig_xml = $clusterConfig_xml -replace '<WORKERIP/>', "$ipaddress"
$clusterConfig_xml = $clusterConfig_xml -replace '<WORKER_REMOTETCP/>', "8585"

$clusterConfig_xml | Out-File -FilePath "$env:NETMAIL_BASE_DIR\..\Config\clusterConfig.xml"

# Making sure no eclients.dat is present at the worker
If ( Test-Path "$env:NETMAIL_BASE_DIR\var\dbf\eclients.dat" ) {
    Rename-Item -Path "$env:NETMAIL_BASE_DIR\var\dbf\eclients.dat" -NewName "eclients.do_not_use"
}