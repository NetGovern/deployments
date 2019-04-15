<#

.SYNOPSIS
Multitenant Remote Provider folders upgrade

.DESCRIPTION
This script updates the binaries of additional RemoteProvider folders used in multitenant environment.

It will replace each client's folder with the binaries found in the folder RemoteProvider, which is taken care of by the MSI update.
The old version is kept as a backup and the configuration files are restored after the copy is complete.

The script stops and starts the NetGovern services.

#>

Write-Output "`r`nStarting DP upgrade"
Stop-Service NetmailLauncherService
$backup_folder = "bkp_dp_manual_$(get-date -f yymmddhhmmss)"
Write-Output "`r`nBacking up existing DP folders to $($env:NETMAIL_BASE_DIR)\..\$($backup_folder)"
(New-Item -Path "$($env:NETMAIL_BASE_DIR)\.." -Name "$backup_folder" -ItemType "directory") | Out-Null
$dp_folders = (Get-ChildItem -Path "$($env:NETMAIL_BASE_DIR)\.." -Directory | Where-Object {$_.FullName -match "RemoteProvider_"})
foreach ($folder in $dp_folders) { 
    $backup_ok = $True
    Copy-Item -Path "$($folder.FullName)" -Recurse -Destination "$($env:NETMAIL_BASE_DIR)\..\$($backup_folder)"
    if (!($?)) {
        Write-Output "`r`nCannot backup existing DP Folders, please upgrade the DP folders manually"
        $backup_ok = $false
    }
}
if ($backup_ok) { 
    Write-Output "`r`nUpgrading dp folders:"
    foreach ($folder in $dp_folders) {
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