<#

.SYNOPSIS
This script Installs Archive MSI
It installs the prequisite software if the parameter is present

.DESCRIPTION
The script downloads the installation files from a blob location.

.EXAMPLE
.\InstallNetmail.ps1 -prereqs


#>

Param(
    [Parameter()]
    [switch]$prereqs,
    [Parameter()]
    [string]$version
)

#Download Installer
$url = "https://netgovernpkgs.blob.core.windows.net/download/Netmail$($version).zip"
$output = "$PSScriptRoot\Netmail.zip"
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $output)

Expand-Archive -LiteralPath "$PSScriptRoot\Netmail.zip" -DestinationPath "$PSScriptRoot"

# Prereqs
if ( $prereqs.IsPresent ) {
    $url = "https://netgovernpkgs.blob.core.windows.net/download/prereqs.zip"
    $output = "$PSScriptRoot\prereqs.zip"
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $output)

    Expand-Archive -LiteralPath "$PSScriptRoot\prereqs.zip" -DestinationPath "$PSScriptRoot"
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
    sleep $TimerIncrement
    $Timer = $Timer + $TimerIncrement
    $progFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects"
}
If ($Timer -ge $TimerLimit) {
    Write-Output "Netmail installation (install.bat) timed out to create Program Files ($TimerLimit seconds)"
    Exit 1
}
sleep 30
$netmailLogFile = Get-ChildItem -Path "C:\Program Files (x86)\Messaging Architects\_$($version)*" -Filter install.log -Recurse | ForEach-Object { $_.FullName }
$Finished = (Get-Content $netmailLogFile | Select-String "Product: Netmail -- Installation operation completed successfully." -ErrorAction Ignore)
$Timer = 0
$TimerLimit = 900
$TimerIncrement = 10
while ((-Not $Finished) -And ($Timer -lt $TimerLimit)) {
    sleep $TimerIncrement
    $Timer = $Timer + $TimerIncrement
    $Finished = (Get-Content $netmailLogFile | Select-String "Product: Netmail -- Installation operation completed successfully." -ErrorAction Ignore)
}
If ($Timer -ge $TimerLimit) {
    Write-Output "Netmail installation (install.bat) timed out ($TimerLimit seconds)"
    Exit 1
}