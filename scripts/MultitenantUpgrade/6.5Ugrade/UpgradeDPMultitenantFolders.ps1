<#

.SYNOPSIS
Multitenant Remote Provider folders upgrade

.DESCRIPTION
This script updates the binaries of additional RemoteProvider folders used in multitenant environment.

It will replace each client's folder with the binaries found in the folder RemoteProvider, which is taken care of by the MSI update.
The old version is kept as a backup and the configuration files are restored after the copy is complete.

The script stops and starts the NetGovern services.

#>
Param(
    [Parameter()]
    [string]$backup_folder
)

if (!$backup_folder) {
    $backup_folder = "bkp_dp_manual_$(get-date -f yyyyMMddhhmmss)"
}

Write-Output "`r`nStarting DP upgrade"
if ((Get-Service NetmailLauncherService).Status -eq "Running"){
    #Stop-Service NetmailLauncherService -Force
     for($i = 0; $i -le 10; $i++){
                    Stop-Service NetmailLauncherService -ErrorAction SilentlyContinue
                    if ((Get-Service NetmailLauncherService).Status -eq "Stopped" ){ break }
                    Write-Host "Trying to stop local NetmailLauncherService, iteration $i"
                    
                }
}
$clientAccessServices = Get-Service | `
    Where-Object {$_.Name -match "NetGovern Client Access" }
$clientAccessStoppedServices = Get-Service | `
    Where-Object {$_.Name -match "NetGovern Client Access" -and $_.Status -eq "Stopped"}

$timer = 0
$timerLimit = 300
$timerIncrement = 10
while (($clientAccessStoppedServices.count -ne $clientAccessServices.count) -And ($timer -lt $timerLimit)) {
    Write-Output "Waiting for Client Access Services to stop"
    Start-Sleep $timerIncrement
    $timer += $timerIncrement
}
if ($timer -ge $timerLimit) {
    Write-Output "Timed out while waiting Client Access services to stop ($timerLimit seconds)"
    Write-Output "Please check that the services are stopped and try again"
    Exit 1
}
$backupOk = $true #IB:added default value for the variable because the script was not executing Upgrading dp folders: section when it is empty
Write-Output "`r`nBacking up existing DP folders to $($env:NETMAIL_BASE_DIR)\..\$($backup_folder)"
(New-Item -Path "$($env:NETMAIL_BASE_DIR)\.." -Name "$backup_folder" -ItemType "directory") | Out-Null
$dpFolders = (Get-ChildItem -Path "$($env:NETMAIL_BASE_DIR)\.." -Directory | Where-Object {$_.FullName -match "RemoteProvider_"})
foreach ($folder in $dpFolders) { 
    Copy-Item -Path "$($folder.FullName)" -Recurse -Destination "$($env:NETMAIL_BASE_DIR)\..\$($backup_folder)"
    if (!($?)) {
        Write-Output "`r`nCannot backup existing DP Folders, please upgrade the DP folders manually"
        $backupOk = $false
    }
}
if ($backupOk) { 
    Write-Output "`r`nUpgrading dp folders:"
    foreach ($folder in $dpFolders) {
        if ($folder.Name -ne "RemoteProvider") {
            Write-Output "`r`nProcessing: $($folder.Name)"
            Write-Output "Removing previous version"
            try { 
                Remove-Item $folder.FullName -Recurse -ErrorAction Stop
            } catch {
                Write-Output "Cannot delete $($folder.FullName).  Please verify that the folder is fully upgraded after the script is finished."
            }
            Write-Output "Recreating new DP version: $($folder.Name)"
            Copy-Item -Path "$($env:NETMAIL_BASE_DIR)\..\RemoteProvider" `
                -Destination "$($env:NETMAIL_BASE_DIR)\..\$($folder.Name)" `
                -Force -Recurse
            Copy-Item -Path "$($env:NETMAIL_BASE_DIR)\..\$($backup_folder)\$($folder.Name)\xgwxmlv.cfg" `
                -Destination "$($env:NETMAIL_BASE_DIR)\..\$($folder.Name)" -Force
            Copy-Item -Path "$($env:NETMAIL_BASE_DIR)\..\$($backup_folder)\$($folder.Name)\jetty-ssl.xml" `
                -Destination "$($env:NETMAIL_BASE_DIR)\..\$($folder.Name)" -Force
            Copy-Item -Path "$($env:NETMAIL_BASE_DIR)\..\$($backup_folder)\$($folder.Name)\WebContent\config.xml" `
            -Destination "$($env:NETMAIL_BASE_DIR)\..\$($folder.Name)\WebContent" -Force
        }
    }
}
Write-Output "`r`nRemote Provider Upgrade finished"
Write-Output "`r`nStarting DP Service"
Start-Service NetmailLauncherService
Write-Output "DP Folders Upgrade Finished"