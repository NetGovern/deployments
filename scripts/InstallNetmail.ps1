<#

.SYNOPSIS
This script Installs Archive MSI
It installs the prequisite software if the parameter is present

.DESCRIPTION
The script downloads the installation files from a blob location.


.EXAMPLE
.\InstallNetmail.ps1 -prereqs -version 6.2.1.844 
This downloads and installs pre requisite software and configuration.  It also downloads "Netmail6.2.1.844.zip" and installs it.

.\InstallNetmail.ps1 -prereqs
This downloads and installs pre requisite software and configuration.  It also downloads "Netmail.zip" and installs it.

.\InstallNetmail.ps1
This downloads and installs "Netmail.zip".

#>

Param(
    [Parameter()]
    [switch]$prereqs,
    [Parameter()]
    [string]$version
)

function Unzip {
    Param(
        [Parameter(Mandatory=$True)]
        [string]$path_to_zip,
        [Parameter(Mandatory=$True)]
        [string]$target_dir
     )
    if ( $PSVersionTable.PSVersion.Major -eq 4) {
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$path_to_zip", "$target_dir")
    }
    if ( $PSVersionTable.PSVersion.Major -ge 5) {
        Expand-Archive -LiteralPath "$path_to_zip" -DestinationPath "$target_dir"
    }
}

# Checking  PSH Version
if ( $PSVersionTable.PSVersion.Major -lt 4 ) {
    Write-Output "Powershell version not supported: $($PSVersionTable.PSVersion.Major)"
}

# Download Installer
$url = "https://netgovernpkgs.blob.core.windows.net/download/Netmail$($version).zip"
$output = "$PSScriptRoot\Netmail.zip"
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $output)
Unzip -path_to_zip "$output" -target_dir "$PSScriptRoot"


# Prereqs
if ( $prereqs.IsPresent ) {
    $url = "https://netgovernpkgs.blob.core.windows.net/download/prereqs.zip"
    $output = "$PSScriptRoot\prereqs.zip"
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $output)
    Unzip -path_to_zip "$output" -target_dir "$PSScriptRoot"
    . ( "$PSScriptRoot\prereqs\InstallPreRequisites.ps1" )
}

# Launche Install.bat
$path2Installbat = "$PSScriptRoot\Netmail\install.bat"
$InstallNetmailArgument = "/c " + $path2Installbat
$InstallNetmailWorkingDir = "$PSScriptRoot\Netmail"
try {
    Start-Process cmd -ArgumentList $InstallNetmailArgument -WorkingDirectory $InstallNetmailWorkingDir
}
Catch {
    Write-Output "Cannot launch install.bat"
    Exit 1
}

$progFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects"
$Timer = 0
$TimerLimit = 180
$TimerIncrement = 10
while ((-Not $progFilesPath) -And ($Timer -lt $TimerLimit)) {
    Start-Sleep $TimerIncrement
    $Timer = $Timer + $TimerIncrement
    $progFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects"
}
If ($Timer -ge $TimerLimit) {
    Write-Output "Netmail installation (install.bat) timed out to create Program Files ($TimerLimit seconds)"
    Exit 1
}
Start-Sleep 30
$netmailLogFile = Get-ChildItem -Path "C:\Program Files (x86)\Messaging Architects\_$($version)*" -Filter install.log -Recurse | ForEach-Object { $_.FullName }
$Finished = (Get-Content $netmailLogFile | Select-String "Product: Netmail -- Installation operation completed successfully." -ErrorAction Ignore)
$Timer = 0
$TimerLimit = 1800
$TimerIncrement = 10
while ((-Not $Finished) -And ($Timer -lt $TimerLimit)) {
    Start-Sleep $TimerIncrement
    $Timer = $Timer + $TimerIncrement
    $Finished = (Get-Content $netmailLogFile | Select-String "Product: Netmail -- Installation operation completed successfully." -ErrorAction Ignore)
}
If ($Timer -ge $TimerLimit) {
    Write-Output "Netmail installation (install.bat) timed out ($TimerLimit seconds)"
    Exit 1
}

Start-Sleep 30
Restart-Service -Name NetmailLauncherService