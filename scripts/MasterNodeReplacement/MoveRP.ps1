<#

.SYNOPSIS
This script moves and configures the remote provider from the old Master and configures it in the local machine

#>
Param(
    [Parameter()]
    [String]$windowsAdminUser= "Administrator",
    [Parameter(Mandatory)]
    [String]$windowsAdminPassword,
    [Parameter(Mandatory)]
    [String]$oldMaster,
    [Parameter(Mandatory)]
    [String]$newMaster
)

$myName =  ($PSCommandPath -split '\\')[-1]
Write-Output "`r`nRunning $myName"

$windowsAdminPasswordSecureString = $windowsAdminPassword | ConvertTo-SecureString -AsPlainText -Force
$windowsAdminCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windowsAdminUser, $windowsAdminPasswordSecureString

Write-Output "Verify SMB ports port at $oldMaster"
#Map the drive
Write-Output "Mapping oldMaster $oldMaster\c$\Program Files (x86)\Messaging Architects"
Try {
    New-PSDrive -name "oldMaster" -PSProvider FileSystem `
        -Root "\\$oldMaster\c$\Program Files (x86)\Messaging Architects" `
        -Credential $windowsAdminCredentials
}
catch {
    Write-Output "Cannot map \\$oldMaster\c$\Program Files (x86)\Messaging Architects as user: $windowsAdminUser"
    Write-Output "Remote Provider needs to be configured manually"
}
Write-Output "oldMaster: mapped successfully"

Write-Output "Copying oldMaster:\RemoteProvider\xgwxmlv.cfg"
Copy-Item -Path "oldMaster:\RemoteProvider\xgwxmlv.cfg" `
    -Destination "$env:NETMAIL_BASE_DIR\..\RemoteProvider" -Force
Write-Output "Copying oldMaster:\RemoteProvider\jetty-ssl.cfg"
Copy-Item -Path "oldMaster:\RemoteProvider\jetty-ssl.xml" `
    -Destination "$env:NETMAIL_BASE_DIR\..\RemoteProvider" -Force
Write-Output "Copying oldMaster:\RemoteProvider\WebContent\config.xml"
Copy-Item -Path "oldMaster:\RemoteProvider\WebContent\config.xml" `
    -Destination "$env:NETMAIL_BASE_DIR\..\RemoteProvider\WebContent" -Force

#Copy nipe properties
Write-Log "`r`nCopy nipe properties" $logfile -toStdOut
Copy-Item "oldMaster:\Nipe\Config\nipeSearcher.properties" `
    -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config" -Force

Remove-PSDrive -Name oldMaster

Write-Output "Updating properties with $newMaster"
$jettySsl = Get-content -Path "$env:NETMAIL_BASE_DIR\..\RemoteProvider\jetty-ssl.xml"
$jettySsl.Replace($oldMaster, $newMaster) | Out-File `
    -FilePath "$env:NETMAIL_BASE_DIR\..\RemoteProvider\jetty-ssl.xml" -Encoding ascii
$xgwxmlv = Get-content -Path "$env:NETMAIL_BASE_DIR\..\RemoteProvider\xgwxmlv.cfg"
$xgwxmlv.Replace($oldMaster, $newMaster) | Out-File `
    -FilePath "$env:NETMAIL_BASE_DIR\..\RemoteProvider\xgwxmlv.cfg" -Encoding ascii

Write-Output "Updating platform nodeinfo"
$json = Get-Content $env:NETMAIL_BASE_DIR\var\docroot\info\netmail-remote-provider
$objFromJson = $json | ConvertFrom-Json
$objFromJson | add-member -Name "configured" -value ($true) -MemberType NoteProperty
$objFromJson | ConvertTo-Json | Out-File $env:NETMAIL_BASE_DIR\var\docroot\info\netmail-remote-provider -Encoding ascii
$objFromJson | ConvertTo-Json
Write-Output "Enabling Client Access Service"
$rpServiceConfPath = "$env:NETMAIL_BASE_DIR\etc\launcher.d\60-awa.conf"
Set-Content -Value "group set `"NetGovern Client Access`" `"Provides support for client access to NetGovern`"" `
    -Path $rpServiceConfPath
Add-Content -Value "start -name awa `"$env:NETMAIL_BASE_DIR\..\RemoteProvider\XAWAService.exe`"" `
    -Path $rpServiceConfPath

Write-Output "Opening Firewall Ports"
$sslPort = [xml]((Select-String -Path "$env:NETMAIL_BASE_DIR\..\RemoteProvider\jetty-ssl.xml" -Pattern 'Set name="port"').Line.Trim())
$sslPort = [int]$sslPort.Set.'#text'
$httpPort = (Select-String -Path "$env:NETMAIL_BASE_DIR\..\RemoteProvider\xgwxmlv.cfg" -Pattern 'provider.http.port').Line.Trim()
if ($httpPort -notmatch "^\#") {
    $trash,$httpPort  = ($httpPort -split "=", 2).Trim()
}
New-NetFirewallRule -DisplayName "NetGovern_RemoteProvider_HTTP" -Name "NetGovern_RemoteProvider_HTTP" -Profile Any -LocalPort $httpPort -Protocol TCP
New-NetFirewallRule -DisplayName "NetGovern_RemoteProvider_HTTPS" -Name "NetGovern_RemoteProvider_HTTPS" -Profile Any -LocalPort $sslPort -Protocol TCP

Write-Output "Script $myName Finished`r`n"