<#

.SYNOPSIS
This script configures the DP in a shared Remote Provider server

.DESCRIPTION
The script should run from an already configured Master server.

.EXAMPLE
.\ConfigureDP.ps1 -rp_server_address 1.1.1.1 -rp_admin_user administrator -rp_admin_password ThePassword -smtp_server 2.2.2.2 -smtp_port 25

.NOTES
It outputs to console the http port for this DP that is configured in the shared Remote Provider server

#>

Param(
    [Parameter()]
    [string]$rp_server_address,
    [Parameter()]
    [string]$rp_admin_user,
    [Parameter()]
    [string]$rp_admin_password,
    [Parameter()]
    [string]$smtp_server,
    [Parameter()]
    [string]$smtp_server_port
)

$rp_admin_secure_string_password = ConvertTo-SecureString $rp_admin_password -AsPlainText -Force
$rp_credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $rp_admin_user, $rp_admin_secure_string_password

#Map the drive
New-PSDrive -name "DP" -PSProvider FileSystem -Root "\\$rp_server_address\c$\Program Files (x86)\Messaging Architects" -Credential $rp_credentials

#Find next available port
$ssl_ports_array = @()
$http_ports_array = @()
Get-ChildItem -Path  "DP:\Netmail Webadmin\etc\launcher.d" -Filter 60-awa*.conf |
Foreach-Object {
    $ssl_port = 0
    $http_port = 0
    $a = Select-String -Path $_.FullName -Pattern "start" # | Out-String
    $splitString = [regex]::Split( $a.Line, ' (?=(?:[^"]|"[^"]*")*$)' )

    $remote_path = Split-Path ($splitString[3] -replace '"','')
    $ssl_port = [xml]((Select-String -Path "$remote_path\jetty-ssl.xml" -Pattern 'Set name="port"').Line.Trim())
    $http_port = (Select-String -Path "$remote_path\xgwxmlv.cfg" -Pattern 'provider.http.port').Line.Trim()
    if ($http_port -notmatch "^\#") {
            $trash,$http_port  = ($http_port -split "=", 2).Trim()
    }

    $http_ports_array += [int]$http_port
    $ssl_ports_array += [int]$ssl_port.Set.'#text'
}

$i = 0
while ($i -ne $http_ports_array.Count) {
    $next = $http_ports_array[$i] + 1
    if ( !$http_ports_array.Contains($next) ) { 
        $http_free_port = $next
        break
    }
    $i += 1
}

$i = 0
while ($i -ne $ssl_ports_array.Count) {
    $next = $ssl_ports_array[$i] + 1
    if ( !$ssl_ports_array.Contains($next) ) { 
        $ssl_free_port = $next
        break
    }
    $i += 1
}

#Create the new folder and replace config
If ( Test-Path "DP:\RemoteProvider_$tenant_id" ) {
    Write-Host "Folder already exists: RemoteProvider_$tenant_id"
    Exit
}
Write-Host "Create DP folder for $tenant_id"
Copy-Item 'DP:\RemoteProvider' -Destination "DP:\RemoteProvider_$tenant_id" -Recurse -Force

Write-Host "Overwrite Default xgwxmlv.cfg with template"
Copy-Item 'DP:\ConfigTemplates\DP\xgwxmlv.cfg' -Destination "DP:\RemoteProvider_$tenant_id\" -Force

Write-Host "Configure jetty-ssl.xml"
$jetty_ssl = Get-content -Path ("DP:\RemoteProvider_$tenant_id\jetty-ssl.xml")
$jetty_ssl -replace 'port".+', "port`">$ssl_free_port</Set>" | Out-File -FilePath "DP:\RemoteProvider_$tenant_id\jetty-ssl.xml"

Write-Host "Configure xgwxmlv.cfg"
#Getting data from master config files
$edir_properties_nipe_master = "$env:NETMAIL_BASE_DIR\..\Nipe\Config\edir.properties"
$cluster_config_conn_string = (Select-String 'PRMS' "$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml").Line
[regex]$loginpwdclear_regex='PASSWORD=".*?"'
$loginpwdclear = ($loginpwdclear_regex.Matches($cluster_config_conn_string) |`
    ForEach-Object {$_.Value}).replace('"', '').split('=')[1]

$ipaddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address

#Regex and replace party
$xgwxmlv_cfg = Get-content -Path ("DP:\RemoteProvider_$tenant_id\xgwxmlv.cfg")
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "provider.http.port=.+", "provider.http.port=$http_free_port" 
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "auth.method=.+", "auth.method="
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "edir.eclientdn", "#edir.eclientdn"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "SMTP.server=.+", "SMTP.server=$smtp_server"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "SMTP.port=.+", "SMTP.port=$smtp_port"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "mopen.host=.+", "mopen.host=$ipaddress"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "cloud.enabled=.+", "cloud.enabled=true"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "cloud.nipe_list=.+", "cloud.nipe_list=http://$($ipaddress):8088"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "cloud.white_list=.+", "cloud.white_list=$ipaddress,$rp_server_address"

$xgwxmlv_cfg = $xgwxmlv_cfg -replace "edir.host=.+", `
    "edir.host=$(((Select-String 'edir.host=' $edir_properties_nipe_master).Line -split '=',2)[1])"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "edir.logindn=.+", `
    "edir.logindn=$(((Select-String 'edir.logindn=' $edir_properties_nipe_master).Line -split '=',2)[1])"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "edir.port=.+", `
    "edir.port=$(((Select-String 'edir.port=' $edir_properties_nipe_master).Line -split '=',2)[1])"
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "edir.container=.+", `
    "edir.container=$(((Select-String 'edir.container=' $edir_properties_nipe_master).Line -split '=',2)[1])"

$xgwxmlv_cfg | Out-File -FilePath "DP:\RemoteProvider_$tenant_id\xgwxmlv.cfg"

Write-Host "Create launcher config file"
"group set `"Netmail Client Access $tenant_id`" `"Netmail Client Access $tenant_id`"" | `
    Out-File -FilePath "DP:\Netmail WebAdmin\etc\launcher.d\60-awa_$tenant_id.conf"
"start -name $tenant_id `"C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\..\RemoteProvider_$tenant_id\XAWAService.exe`"" | `
    Out-File -Append -FilePath "DP:\Netmail WebAdmin\etc\launcher.d\60-awa_$tenant_id.conf"
Remove-PSDrive -Name DP

Write-Output $http_free_port




