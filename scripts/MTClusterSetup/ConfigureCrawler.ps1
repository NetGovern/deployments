<#

.SYNOPSIS
The script must be run on CRAWLER node.
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


#IB: just in case there are smb connections to Dp
Restart-Service -Name "LanmanWorkstation" -Force



function DisconnectMappedPSDrives {
    Remove-PSDrive -Name MASTER -ErrorAction SilentlyContinue
    Remove-PSDrive -Name DP -ErrorAction SilentlyContinue
}

Set-Location $PSScriptRoot

#Source functions and config templates
. .\ngfunctions.ps1
. .\basedata.ps1

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

Write-Output "Stopping Service"
Stop-Service -Name NetmailLauncherService

Write-Output "Configuring Open Thread Pool"
#Create "55-open.conf"
$55_open_path = "$env:NETMAIL_BASE_DIR\etc\launcher.d\55-open.conf"
Set-Content -Value 'group set "NetGovern Archive" "Provides support for parallel processing of NetGovern jobs"' `
    -Path $55_open_path
Add-Content -Value 'start -name archive "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\..\MAThreadPool.exe"' `
    -Path $55_open_path

#Create "55-archiving.conf"
$55_archiving_path = "$env:NETMAIL_BASE_DIR\etc\launcher.d\55-archiving.conf"
Set-Content -Value 'group set "NetGovern Archiving Service" "Archiving external data in the NetGovern Archive"' `
    -Path $55_archiving_path
Add-Content -Value 'start -name archivingService "%NETMAIL_BASE_DIR%\..\netcore\Archive\Netgovern.Services.Archiving.exe"' `
    -Path $55_archiving_path

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


# Create nodeid.cfg
Set-Content -Value $ipaddress -Path ".\nodeid.cfg"
Copy-Item ".\nodeid.cfg" -Destination "$env:NETMAIL_BASE_DIR\..\Config" -Force

# Create clusterConfig.xml
$clusterConfig_xml = Get-content -Path ("$env:NETMAIL_BASE_DIR\..\Config\clusterConfigWorker.xml")
$clusterConfig_xml = $clusterConfig_xml -replace '<MASTERIP/>', "$master_server_address"
$clusterConfig_xml = $clusterConfig_xml -replace '<MASTER_REMOTETCP/>', "8585"

#IB:Skip adding crawler as worker node
#$clusterConfig_xml = $clusterConfig_xml -replace '<NOPEIP/>', "$ipaddress"
#$clusterConfig_xml = $clusterConfig_xml -replace '<WORKERIP/>', "$ipaddress"
#$clusterConfig_xml = $clusterConfig_xml -replace '<WORKER_REMOTETCP/>', "8585"

Set-Content -Value $clusterConfig_xml -Path ".\clusterConfig.xml" #debug

$clusterConfig_xml | Out-File -FilePath "$env:NETMAIL_BASE_DIR\..\Config\clusterConfig.xml" -Encoding ascii -Force

# Making sure no eclients.dat is present at the worker
If ( Test-Path "$env:NETMAIL_BASE_DIR\var\dbf\eclients.dat" ) {
    Rename-Item -Path "$env:NETMAIL_BASE_DIR\var\dbf\eclients.dat" -NewName "eclients.do_not_use"
}

Write-Output "Restart Launcher" 
Restart-Service -Name NetmailLauncherService
Start-Sleep 30


Write-Output "Allowing Local Subnet in the firewall"
try { New-NetFirewallRule `
        -DisplayName "NetGovern_Allow_Local_Subnet" `
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

Write-Output "Configuring Nipe Service"
Copy-Item -Path "$env:NETMAIL_BASE_DIR\..\ConfigTemplates\Nipe\netmail.properties" `
    -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config\"
Copy-Item -Path "MASTER:\Nipe\Config\edir.properties" `
    -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config\"
Copy-Item -Path "MASTER:\Nipe\Config\solr.properties" `
    -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config\"

#Create "50-indexer.conf"
$50_indexer_path = "$env:NETMAIL_BASE_DIR\etc\launcher.d\50-indexer.conf"
Set-Content -Value 'group set "NetGovern Indexer" "Runs Netmail Indexing services"' `
    -Path $50_indexer_path
Add-Content -Value 'start -name indexer "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\..\Nipe\IndexerService.exe"' `
    -Path $50_indexer_path

Write-Output "Setting up crawlerproxy at MASTER's warpd"
$crawler_proxy_json = Get-content -Path ("MASTER:\Netmail Webadmin\etc\warp-config.d\crawlerproxy.json")
if (!($crawler_proxy_json -match "127.0.0.1")) {
    Write-Output "This Tenant already has a crawler already, at this moment only 1 crawler node per tenant is supported"
    Write-Output "Cancelling script"
    DisconnectMappedPSDrives
    Exit 1
}

$crawler_proxy_json = $crawler_proxy_json -replace "127.0.0.1", "$ipaddress" 

Set-Content -Value $crawler_proxy_json -Path ".\crawlerproxy.json" #debug

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


#Stop NetGovern services
if ((get-service NetmailLauncherService).status -eq "Running"){
Write-Host "Stoping NetGovern services"
Stop-Service -Name NetmailLauncherService
} else{Write-Host "NetGovern services is not running"}

Write-Output "Configure ldap connection in applicationContext.xml"
$application_context_xml_path = "$env:NETMAIL_BASE_DIR\..\Crawler\conf\applicationContext.xml"
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

#IB:Edit applicationContext.xml adding apid key
$unixdate = [int][double]::Parse((Get-Date -UFormat %s))
Copy-item "c:\Program Files (x86)\Messaging Architects\Crawler\conf\applicationContext.xml" -Destination "c:\Program Files (x86)\Messaging Architects\Crawler\conf\applicationContext.xml$unixdate"
Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force
$key = UpdateapplicationContext -tenantID $ldap.tenant_id

#addressing NM-29304
Write-Output "Updating servicesettings.json"
$apiurl = "https://"+$master_server_address+":444"
Copy-Item -Path "$env:NETMAIL_BASE_DIR\..\netcore\archive\servicesettings.json" -Destination "$env:NETMAIL_BASE_DIR\..\netcore\archive\servicesettings.json_$unixdate "
$servicesettings = Get-Content -Raw -Path "$env:NETMAIL_BASE_DIR\..\netcore\archive\servicesettings.json" |ConvertFrom-Json
$servicesettings.Netgovern.AdminAPI.Key = $key[($key.Count) -1]
$servicesettings.Netgovern.AdminAPI.URLs = [Object[]]"$apiurl"
Write-Output "Set content ot  $env:NETMAIL_BASE_DIR\..\netcore\archive\servicesettings.json"
$servicesettings|ConvertTo-Json -Depth 50 |Set-Content -Path "$env:NETMAIL_BASE_DIR\..\netcore\archive\servicesettings.json" -Force
Copy-Item -Path "$env:NETMAIL_BASE_DIR\..\netcore\archive\servicesettings.json" -Destination "./servicesettings.json"


if ((get-service NetmailLauncherService).status -eq "Running"){
Write-Host "Stoping NetGovern services"
Stop-Service -Name NetmailLauncherService
Write-Host "starting NetGovern services"
Start-Service -Name NetmailLauncherService
} else{
    Write-Host "NetGovern services is not running"
    Write-Host "starting NetGovern services"
    Start-Service -Name NetmailLauncherService
    }


#Setup crawler
Write-Output "Setting up Crawler with DB server: $($db_conn_object.server) and DB: $($db_conn_object.database)"

Write-Output "Setting up Crawler with DB server: $($db_conn_object.server) and DB: $($db_conn_object.database)"
$win_setup_crawler_bat_cmd = "`"$env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-SetupCrawler.bat`" $($db_conn_object.server) $ipaddress netmail $netmail_user_password $($db_conn_object.database) $postgres_password"
$setup_crawler_output = cmd.exe /c $win_setup_crawler_bat_cmd 2`>`&1
$setup_crawler_output | Tee-Object -FilePath  ".\setup_crawler_output.txt" #IB:tee to display the status in a console 
if (!($LASTEXITCODE -eq 0)) {
     Write-Output "Crawler setup failed at $win_setup_crawler_bat_cmd"
     Write-Output "Cancelling script"
     DisconnectMappedPSDrives
     Exit 1
    }

#edit xgwxmlv
Write-Output "Add crawler to DP configuration file: cloud.crawler_list=https://$($ipaddress)/unifyle"
$unixdate = [int][double]::Parse((Get-Date -UFormat %s))
Copy-Item -Path "DP:\RemoteProvider_$($ldap.tenant_id)\xgwxmlv.cfg" -Destination "DP:\RemoteProvider_$($ldap.tenant_id)\xgwxmlv.cfg_$unixdate"
$xgwxmlv_cfg_path = "DP:\RemoteProvider_$($ldap.tenant_id)\xgwxmlv.cfg"
$xgwxmlv_cfg = Get-content -Path $xgwxmlv_cfg_path
$xgwxmlv_cfg = $xgwxmlv_cfg -replace "^cloud.crawler_list=.*", "cloud.crawler_list=https://$($ipaddress)/unifyle" #removed the  port 7979 it si not requiered anymore

Set-Content -Value $xgwxmlv_cfg -Path ".\xgwxmlv.cfg" #debug
try {
    $xgwxmlv_cfg | Out-File -FilePath $xgwxmlv_cfg_path -Encoding ascii -ErrorAction Stop
} catch {
    Write-Output "Cannot write to: $xgwxmlv_cfg_path"
    Write-Output "Please edit it manually"
}

Write-Output "Configuring mdb.conf"
$mdb_conf = Get-Content "MASTER:\Netmail WebAdmin\etc\mdb.conf" 
$mdb_conf = $mdb_conf -replace "Driver=MDBLDAP machine=.+basedn", "Driver=MDBLDAP machine=$env:COMPUTERNAME&basedn"

Set-Content -Value $mdb_conf -Path ".\mdb.conf" #debug

$mdb_conf | Out-File "$env:NETMAIL_BASE_DIR\etc\mdb.conf" -Encoding ascii

#restarting remote services
$service = $null
Write-Output "Restart Launcher"
Restart-Service -Name NetmailLauncherService
Write-Output "Restart Launcher $rp_server_address"
$service = Get-Service -ComputerName $rp_server_address -Name "NetmailLauncherService"
Restart-Service -InputObject $service -Verbose
Write-Output "Restart Launcher $master_server_address"
$service = Get-Service -ComputerName $master_server_address -Name "NetmailLauncherService"
Restart-Service -InputObject $service -Verbose
Write-Output "Restart Launcher"
Restart-Service -Name NetmailLauncherService


DisconnectMappedPSDrives
Write-Output "Finished"
