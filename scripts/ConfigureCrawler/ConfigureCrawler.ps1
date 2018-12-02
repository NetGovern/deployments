<#

.SYNOPSIS
This script configures a node as a crawler node for a multitenant master

.DESCRIPTION
The script should run from an deployed Archive VM, it needs to be able to access the Master Administrative share C$.
It also needs to access the Administrative shared C$ at the Remote Provider Server

.EXAMPLE
.\ConfigureCrawler.ps1 -master_server_address 1.1.1.1 -master_admin_user administrator `
    -master_admin_password ThePassword -netmail_user_password AnotherPassword `
    -postgres_password PostgresPassword `
    -rp_server_address 1.1.1.2 -rp_admin_user administrator -rp_admin_password AnotherOne


#>

Param(
    [Parameter()]
    [string]$master_server_address,
    [Parameter()]
    [string]$master_admin_user,
    [Parameter()]
    [string]$master_admin_password,
    [Parameter()]
    [string]$netmail_user_password,
    [Parameter()]
    [string]$postgres_password,
    [Parameter()]
    [string]$rp_server_address,
    [Parameter()]
    [string]$rp_admin_user,
    [Parameter()]
    [string]$rp_admin_password
)

function DisconnectMappedPSDrives {
    Remove-PSDrive -Name MASTER -ErrorAction SilentlyContinue
    Remove-PSDrive -Name DP -ErrorAction SilentlyContinue
}

Set-Location $PSScriptRoot

#Source functions and config templates
. .\ngfunctions.ps1

Write-Output "Connecting to Master: $master_server_address and Remote Provider: $rp_server_address"
$master_admin_secure_string_password = ConvertTo-SecureString $master_admin_password -AsPlainText -Force
$master_credentials = new-object -typename System.Management.Automation.PSCredential `
    -argumentlist $master_admin_user, $master_admin_secure_string_password

Write-Output "Connecting to Master: $master_server_address as $master_admin_user"
try { New-PSDrive `
        -name "MASTER" `
        -PSProvider FileSystem `
        -Root "\\$master_server_address\c$\Program Files (x86)\Messaging Architects" `
        -Credential $master_credentials `
        -ErrorAction Stop `
        > $null
} catch {
    Write-Output "Cannot connect to Master: $master_server_address"
    Write-Output "Cancelling Configuration script"
    Exit 1
}

$rp_admin_secure_string_password = ConvertTo-SecureString $rp_admin_password -AsPlainText -Force
$rp_credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $rp_admin_user, $rp_admin_secure_string_password
Write-Output "Connecting to Remote Provider: $rp_server_address as $rp_admin_user"
try { New-PSDrive `
        -name "DP" `
        -PSProvider FileSystem `
        -Root "\\$rp_server_address\c$\Program Files (x86)\Messaging Architects" `
        -Credential $rp_credentials `
        -ErrorAction Stop `
        > $null
} catch {
    Write-Output "Cannot connect to Remote Provider: $rp_server_address"
    Write-Output "Exiting Configuration script"
    Exit 1
}

Write-Output "Restart Launcher to make sure it's up and running" 
Restart-Service -Name NetmailLauncherService
Start-Sleep 30

try { $ipaddress = `
    (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 -ErrorAction Stop| `
        Select-Object IPV4Address).IPV4Address
} catch {
    Write-Output "Cannot get my own IP address.  Check Network settings."
    Write-Output "Exiting Configuration script"
    DisconnectMappedPSDrives
    Exit 1
} 
Write-Output "My IP address is: $ipaddress"

Write-Output "Allowing Local Subnet in the firewall"
try { New-NetFirewallRule `
        -DisplayName "Netmail_Allow_Local_Subnet" `
        -Direction Inbound `
        -Profile 'Domain', 'Private', 'Public' `
        -Action Allow `
        -RemoteAddress LocalSubnet `
        -ErrorAction Stop
} catch {
    Write-Output "Cannot create firewall rule, please allow LocalSubnet manually"
}

Write-Output "Configure CFS Cluster" # Needed ?, adding it for consistency
$cfs_conf_test = Test-Path "$env:NETMAIL_BASE_DIR\etc\cfs.conf"
if ( $cfs_conf_test ) {
    $cfs_conf = ((Get-content $env:NETMAIL_BASE_DIR\etc\cfs.conf) -join "`n" | ConvertFrom-Json).psobject.properties
    if ($cfs_conf['ip'].Value.split(':')[0] -eq $ipaddress) {
        Write-Output "CFS Cluster already configured, skipping"
    } else {
        Write-Output "Create New CFS Cluster" 
        & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-ConfigureCFS.bat new $ipaddress
    }
} else {
    Write-Output "Create New CFS Cluster" 
    & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-ConfigureCFS.bat new $ipaddress
}


Write-Output "Setting up crawlerproxy at MASTER's warpd"
$crawler_proxy_json = Get-content -Path ("MASTER:\Netmail Webadmin\etc\warp-config.d\crawlerproxy.json")
if (!($crawler_proxy_json -match "127.0.0.1")) {
    Write-Output "This Tenant already has a crawler already, at this moment only 1 crawler node per tenant is supported"
    Write-Output "Cancelling script"
    DisconnectMappedPSDrives
    Exit 1
}

$crawler_proxy_json = $crawler_proxy_json -replace "127.0.0.1", "$ipaddress" 
$crawler_proxy_json | Out-File -FilePath "MASTER:\Netmail Webadmin\etc\warp-config.d\crawlerproxy.json" -Encoding ascii

Write-Output "Gathering LDAP connection info from Master: $master_server_address"
$ldap = ParseEdirProperties "MASTER:\Nipe\Config\edir.properties"

$ldapsearch = "$env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe" 
$base_dn = "cn=GWOpenNode," + $($ldap.edir_container)
#ldap query
$params = "-D `"$($ldap.logindn)`" -o ldif-wrap=200 -w $($ldap.loginpwdclear) -p $($ldap.port) -h $($ldap.host) -b `"${base_dn}`" `"objectclass=maGWOpenNode`" maLogCnnString"
Write-Host "Query LDAP: $($ldap.host) as $($ldap.logindn) searching for Postgres DB name and location"
try {
    $ldif = Invoke-Expression "& `"$ldapsearch`" $params" -ErrorAction Stop
} catch {
    Write-Output "LDAP Query failed, cancelling script"
    DisconnectMappedPSDrives
    Exit 1    
} 
#parse ldif results
$db_conn_string = $ldif | Select-String "maLogCnnString:"
$db_conn_string = ($($db_conn_string.Line) -split ': ')[1]
$db_conn_object = (ParseSQLConnString $db_conn_string)

Write-Output "Setting up Crawler with DB server: $($db_conn_object.server) and DB: $($db_conn_object.database)"
$win_setup_crawler_bat_cmd = "`"$env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-SetupCrawler.bat`" $($db_conn_object.server) $ipaddress netmail $netmail_user_password $($db_conn_object.database) $postgres_password"
$setup_crawler_output = cmd.exe /c $win_setup_crawler_bat_cmd 2`>`&1
$setup_crawler_output | Out-File "setup_crawler_output.txt" -Encoding ascii
if (!($LASTEXITCODE -eq 0)) {
    Write-Output "Crawler setup failed at $win_setup_crawler_bat_cmd"
    Write-Output "Cancelling script"
    DisconnectMappedPSDrives
    Exit 1
}

#Stop Netmail services
Stop-Service -Name NetmailLauncherService

Write-Output "Configure ldap connection in applicationContext.xml"
$application_context_xml_path = "$env:NETMAIL_BASE_DIR\..\Crawler\apache-tomcat-7.0.40\webapps\unifyle\WEB-INF\classes\applicationContext.xml"
$application_context_xml = Get-Content $application_context_xml_path
$n = 0
$application_context_xml | ForEach-Object {
    if ($_ -match "ldapHost") {
        $beg = $n - 1
    }
    if ($_ -match "ldapContainer") {
        $end = $n + 1
    }
    $n += 1
}
$application_context_xml = $application_context_xml `
    -replace '<property name="ldapHost" value="1.2.3.4"/>', "<property name=`"ldapHost`" value=`"$($ldap.host)`"/>"
$application_context_xml = $application_context_xml `
    -replace '<property name="ldapLoginDn" value="cn=netmail,cn=system,o=netmail"/>', "<property name=`"ldapLoginDn`" value=`"$($ldap.logindn)`"/>"
$application_context_xml = $application_context_xml `
    -replace '<property name="ldapLoginPwd" value="my_password"/>', "<property name=`"ldapLoginPwd`" value=`"$($ldap.loginpwdclear)`"/>"
$application_context_xml = $application_context_xml `
    -replace '<property name="ldapContainer" value="o=netmail"/>', "<property name=`"ldapContainer`" value=`"$($ldap.edir_container)`"/>"
try {
    $application_context_xml[0] | Out-File $application_context_xml_path -Encoding ascii -ErrorAction Stop
    (1..$($beg - 1)) | ForEach-Object {
        $application_context_xml[$_] | Out-File $application_context_xml_path -Encoding ascii -Append -ErrorAction Stop
    }
    ($($beg + 1)..$($end - 1)) | ForEach-Object {
        $application_context_xml[$_] | Out-File $application_context_xml_path -Encoding ascii -Append -ErrorAction Stop
    }
    ($($end + 1)..$n) | ForEach-Object {
        $application_context_xml[$_] | Out-File $application_context_xml_path -Encoding ascii -Append -ErrorAction Stop
    }
} catch {
    Write-Output "Cannot write to: $application_context_xml_path"
    Write-Output "Please edit it manually"
}

Write-Output "Add crawler to DP configuration file: cloud.crawler_list=https://$($ipaddress):7979/unifyle"
$xgwxmlv_cfg_path = "DP:\RemoteProvider_$($ldap.tenant_id)\xgwxmlv.cfg"
$xgwxmlv_cfg = Get-content -Path $xgwxmlv_cfg_path
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "cloud.crawler_list=.+", "cloud.crawler_list=https://$($ipaddress):7979/unifyle" 
try {
    $xgwxmlv_cfg | Out-File -FilePath $xgwxmlv_cfg_path -Encoding ascii -ErrorAction Stop
} catch {
    Write-Output "Cannot write to: $xgwxmlv_cfg_path"
    Write-Output "Please edit it manually"
}
Write-Output "Restart Launcher"
Restart-Service -Name NetmailLauncherService

DisconnectMappedPSDrives
Write-Output "Finished"