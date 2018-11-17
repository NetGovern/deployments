'''
    It requires The services to be stopped.
    A normal workflow would be to upgrade Netmail, and run this script after.
    It assumes that each DP has the naming convention of NetmailProvider_<tenant_id>

'''

$backup_folder = "bkp_dp_$(get-date -f yymmddhhmmss)"
Write-Output "Backing up existing DP folders to $($env:NETMAIL_BASE_DIR)\..\$backup_folder"
Write-Output "Creating folder $backup_folder"
(New-Item -Path "$($env:NETMAIL_BASE_DIR)\.." -Name "$backup_folder" -ItemType "directory") | Out-Null
$dp_folders = (Get-ChildItem -Path "$($env:NETMAIL_BASE_DIR)\.." -Directory | Where-Object {$_.FullName -match "RemoteProvider"})
Write-Output "Copying dp folders to bkp directory"
foreach ($folder in $dp_folders) { 
    Copy-Item -Path "$($folder.FullName)" -Recurse -Destination "$($env:NETMAIL_BASE_DIR)\..\bkp_dp_$current_version_dp"
}
if ($?) { 
    Write-Output "Upgrading dp folders"
    foreach ($folder in $dp_folders) {
        if ($folder.Name -ne "RemoteProvider") {
            Copy-Item -Path "$($env:NETMAIL_BASE_DIR)\..\RemoteProvider" `
                -Destination "$($env:NETMAIL_BASE_DIR)\..\$($folder.Name)" `
                -Exclude @("xgwxmlv.cfg", "jetty-ssl.xml") -Force -Recurse
        }
    }
} else {
    Write-Output "Cannot backup existing DP Folders, please run DP upgrade manually"
}

Write-Output "DP Folders Upgrade Finished"