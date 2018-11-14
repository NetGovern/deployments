<#

.SYNOPSIS
This script upgrades the nodes found in the specified json file

.DESCRIPTION
The json file contains information about the IP addresses, type of nodes and version discovered previously
It needs windows and linux admin passwords as well as the target version to which upgrade

.EXAMPLE
.\Upgrade.ps1 -discovery_json_file ".\mycluster.json" -windows_admin_user "Administrator" -windows_admin_password "ThePassword" -linux_admin_user netmail -linux_admin_password "ThePassword" -upgrade_version "6.2.1.844"

#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$discovery_json_file,
    [Parameter(Mandatory=$true)]
    [string]$windows_admin_user,
    [Parameter(Mandatory=$true)]
    [string]$windows_admin_password,
    [Parameter(Mandatory=$true)]
    [string]$linux_admin_user,
    [Parameter(Mandatory=$true)]
    [string]$linux_admin_password,
    [Parameter(Mandatory=$true)]
    [string]$upgrade_version
)

# Vars init -  download utils
$install_msi = {
    function Unzip {
        Param(
            [Parameter(Mandatory = $True)]
            [string]$path_to_zip,
            [Parameter(Mandatory = $True)]
            [string]$target_dir
        )
        if ( $PSVersionTable.PSVersion.Major -eq 4) {
            [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$path_to_zip", "$target_dir", $true)
        }
        if ( $PSVersionTable.PSVersion.Major -ge 5) {
            Expand-Archive -LiteralPath "$path_to_zip" -DestinationPath "$target_dir"
        }
    }

    # Checking  PSH Version
    if ( $PSVersionTable.PSVersion.Major -lt 4 ) {
        Write-Output "Powershell version not supported: $($PSVersionTable.PSVersion.Major)"
    }

    Unzip -path_to_zip "C:\Program Files (x86)\Messaging Architects\installer\Netmail.zip" -target_dir "$env:TEMP"

    # Launche Install.bat
    $path2Installbat = "$env:TEMP\Netmail\install.bat"
    $version = ((Get-Content $path2Installbat | Select-String "Update.exe version") -split "Update.exe version=")[1].Trim()
    Write-Output "Upgrading to version: $version"
    $InstallNetmailArgument = "/c " + $path2Installbat
    $InstallNetmailWorkingDir = "$env:TEMP\Netmail"
    try {
        Start-Process cmd -ArgumentList $InstallNetmailArgument -WorkingDirectory $InstallNetmailWorkingDir
    }
    Catch {
        Write-Output "Cannot launch install.bat"
        Exit 1
    }

    $logFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    $Timer = 0
    $TimerLimit = 600
    $TimerIncrement = 10
    while ((-Not $logFilesPath) -And ($Timer -lt $TimerLimit)) {
        Write-Output "Waiting for the upgrade process to start"
        Start-Sleep $TimerIncrement
        $Timer = $Timer + $TimerIncrement
        $logFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    }
    If ($Timer -ge $TimerLimit) {
        Write-Output "Netmail installation (install.bat) timed out to create Log Files folder ($TimerLimit seconds)"
        Exit 1
    }

    $netmailLogFile = "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    $Finished = (Get-Content $netmailLogFile | Select-String "Product: Netmail -- Installation operation completed successfully." -ErrorAction Ignore)
    $Timer = 0
    $TimerLimit = 1800
    $TimerIncrement = 10
    while ((-Not $Finished) -And ($Timer -lt $TimerLimit)) {
        Write-Output "Netmail installing, please wait"
        Get-Content $netmailLogFile -Tail 2
        Start-Sleep $TimerIncrement
        $Timer = $Timer + $TimerIncrement
        $Finished = (Get-Content $netmailLogFile | Select-String "Product: Netmail -- Installation operation completed successfully." -ErrorAction Ignore)
    }
    If ($Timer -ge $TimerLimit) {
        Write-Output "Netmail installation (install.bat) timed out ($TimerLimit seconds)"
        Exit 1
    }
    Write-Output "-----------------------------"
    Write-Output "Netmail Installation Finished"
}

$curl_exe = "$env:NETMAIL_BASE_DIR\etc\scripts\setup\curl.exe"
$params = '-k', '-s', '-O', "https://netgovernpkgs.blob.core.windows.net/download/klink.exe"
Invoke-Expression "& `"$curl_exe`" $params" 
$klink_exe = "$PSScriptRoot\klink.exe"

# Download Installer
$url = "https://netgovernpkgs.blob.core.windows.net/download/Netmail$($upgrade_version).zip"
$curl_download_file_path = "`"$env:NETMAIL_BASE_DIR\..\Installer\Netmail.zip`""
$downloaded_file_path = "$env:NETMAIL_BASE_DIR\..\Installer\Netmail.zip"
$params = '-k', '-o', $curl_download_file_path , $url
if ( ! (test-path -pathtype container "$env:NETMAIL_BASE_DIR\..\installer") ) {
    New-Item -Path "$env:NETMAIL_BASE_DIR\..\" -Name "installer" -ItemType "directory"
}
Write-Output "Downloading Upgrade package"
Invoke-Expression "& `"$curl_exe`" $params"


$windows_admin_password_secure_string = $windows_admin_password | ConvertTo-SecureString -AsPlainText -Force
$admin_credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windows_admin_user, $windows_admin_password_secure_string

Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force

$info_json = Get-Content "$discovery_json_file"
$info_hash = @{}
($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }

$upgrade_me = $false
$jobs = @()

$info_hash['index'].psobject.Properties | foreach-object {
    $node_ip = $_.Name
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            $klink_parameters = "-t", "-auto-store-sshkey","-pw", `
                "${linux_admin_password}", "-l", "${linux_admin_user}", "${node_ip}", `
            "`"wget -P /home/netmail https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/upgrade_rpms.sh && chmod +x /home/netmail/upgrade_rpms.sh && sudo /home/netmail/upgrade_rpms.sh -v ${upgrade_version} -i`""
            $install_rpms_command = "& ${klink_exe} ${klink_parameters} 2>`$null"
            $install_index = [Scriptblock]::Create($install_rpms_command)
            $output_file_name = "Index-$($node_ip)-$(Get-Date -f "MMddhhmmss").txt"
            Write-Output "Starting Index upgrade from $($_.Value) to $upgrade_version"
            try {
                Invoke-Command -ScriptBlock $install_index | Out-File $output_file_name
            } catch {
                Write-Output "Cannot start index upgrade at $node_ip"
                Exit 1
            }
        }
        if ( $($_.Name) -eq "version" -and $($_.Value) -ge $upgrade_version ) {
            Write-Output "Index version is already $($_.Value) ()>= $upgrade_version)"
        }
    }
}
$info_hash['dp'].psobject.Properties | foreach-object {
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            $current_version = $($_.Value)
            $upgrade_me = $True
            Write-Output "Starting DP upgrade"
            Stop-Service NetmailLauncherService
            Write-Output "Backing up existing DP folders to $($env:NETMAIL_BASE_DIR)\..\bkp_dp_$current_version"
            (New-Item -Path "$($env:NETMAIL_BASE_DIR)\.." -Name "bkp_dp_$current_version" -ItemType "directory") | Out-Null
            $dp_folders = (Get-ChildItem -Path "$($env:NETMAIL_BASE_DIR)\.." -Directory | Where-Object {$_.FullName -match "RemoteProvider_"})
            foreach ($folder in $dp_folders) { 
                Copy-Item -Path "$($folder.FullName)" -Recurse -Destination "$($env:NETMAIL_BASE_DIR)\..\bkp_dp_$current_version"
            }
            if ($?) { 
                Write-Output "Starting Netmail Upgrade"
                Invoke-Command -ScriptBlock $install_msi | Out-File "remoteProviderNetmailInstallLog.txt"
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
        }
    }
}
$archive_nodes = @()
$info_hash['archive'].psobject.Properties | foreach-object {
    $node_ip = $_.Name
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            (New-PSDrive -name TEMP -PSProvider FileSystem -Root "\\$node_ip\c$\Program Files (x86)\Messaging Architects" -Credential $admin_credentials) | Out-Null
            if ( ! (test-path -pathtype container "TEMP:\installer") ) {
                (New-Item -Path "TEMP:\" -Name "installer" -ItemType "directory") | Out-Null
            }
            Write-Output "Copying installer to $node_ip"
            Get-ChildItem $downloaded_file_path | Copy-Item -Destination "TEMP:\installer"
            Remove-PSDrive -Name TEMP
            $job_name = "JobAt$($node_ip)-$(Get-Date -f "MMddhhmmss")"
            Write-Output "Starting Archive upgrade job at $node_ip"
            (Invoke-Command -ScriptBlock $install_msi -ComputerName $node_ip -Credential $admin_credentials -AsJob -JobName $job_name) | Out-Null
            if ($?) { 
                $jobs += $job_name
                $archive_nodes += $node_ip
            }
            else { Write-output "Job could not be launched at $node_ip, please run upgrade manually" }
        }
    }
}

#Checking jobs status
$Timer = 0
$TimerLimit = 3600
$TimerIncrement = 10
$jobs_left = $jobs.Count
$progress_bar = "."
Write-Output "Waiting for Jobs to finish"
Get-Job -Name JobAt*
while (($jobs_left -gt 0) -And ($Timer -lt $TimerLimit)) {
    $jobs_left = $jobs.Count
    if ( ($Timer%120) -eq 0 ) {
        Write-Output ""
        Write-Output "Please wait for the remote and background jobs to finish..."
        Get-Job -Name $jobs | Select-Object Name,State,Location
        $progress_bar = ""
    }
    Start-Sleep $TimerIncrement
    Write-Host $progress_bar -NoNewline
    $Timer = $Timer + $TimerIncrement
    $progress_bar += "."
    ForEach ($job_name in $jobs) {
        $job_state = (get-job -Name $job_name).JobStateInfo.State
        if ($job_state -eq "Completed") {
            $jobs_left -= 1 
        }
        get-job -Name $job_name | Receive-Job | Out-File -Append "$($job_name).txt"
    }    
}
If ($Timer -ge $TimerLimit) {
    Write-Output "Remote upgrades timed out after $TimerLimit seconds)"
} else {
    Write-Output ""
    Write-Output "All Remote and background jobs finished"
}

foreach ($archive_node_to_be_started in $archive_nodes) {
    Write-Output "Starting Launcher @ $archive_node_to_be_started"
    try {
        Invoke-Command -ScriptBlock { Start-Service NetmailLauncherService } -ComputerName $archive_node_to_be_started -Credential $admin_credentials
    } catch {
        Write-Output "Cannot start Launcher Service at $archive_node_to_be_started"
    }
}

if ($upgrade_me) {
    Write-Output "Starting DP Service"
    Start-Service NetmailLauncherService
}

