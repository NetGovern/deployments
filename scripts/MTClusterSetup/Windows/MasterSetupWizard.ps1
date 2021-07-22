<#

.SYNOPSIS
This script configures the Archive Master in a multi tenant architecture

.DESCRIPTION
The script should run from an image with the pre-requisites and netmail installed
If you don't have backend , change [switch]$nobackend = $false, to $true. That will set the backend parameters to null.
Fot no bsckend scenario, you must set Identity sync from UUI

.EXAMPLE
.\MasterSetupWizard.ps1 -ldap_server 1.1.1.1 `
    -ldap_admin_dn 'cn=netmail,cn=system,o=netmail' `
    -ldap_admin_password 'The Password' `
    -zookeeper_ip 2.2.2.2 `
    -postgresql_server 3.3.3.3 `
    -postgresql_port 5432 `
    -postgresql_admin_user postgres `
    -postgresql_admin_password 'postgresPassword' `
    -tenant_id tenant01 `
    -netgovern_password 'NetmailPassword' `
    -smtp_server 5.5.5.5 `
    -o365_user 'admin@o365.com' `
    -o365_password 'ExchangePAssword' `
    -o365_url 'https://5.5.5.5/Powershell' `
    -ma_notify_email 'notifyme@o365.com'

#>

Param(
    [Parameter()]
    [string]$ldap_server,
    [Parameter()]
    [string]$ldap_admin_dn,
    [Parameter()]
    [string]$ldap_admin_password,
    [Parameter()]
    [string]$zookeeper_ip,
    [Parameter()]
    [string]$postgresql_server,
    [Parameter()]
    [string]$postgresql_port = "5432",
    [Parameter()]
    [string]$postgresql_admin_user = "postgres",
    [Parameter()]
    [string]$postgresql_admin_password,
    [Parameter()]
    [string]$tenant_id,
    [Parameter()]
    [string]$netgovern_password,
    [Parameter()]
    [string]$smtp_server = "smtp_server",
    [Parameter()]
    [string]$o365_user = "o365_user@onmicrosoft.com",
    [Parameter()]
    [string]$o365_password = "o365_password",
    [Parameter()]
    [string]$o365_url = "https://outlook.office365.com/PowerShell",
    [Parameter()]
    [string]$ma_notify_email = 'ma_notify@email.address',
    [Parameter()]
    [string]$remote_provider_ip_address,
    [Parameter()]
    [string]$remote_provider_admin_user,
    [Parameter()]
    [string]$remote_provider_password,
    [Parameter()]
    [string]$o365_tenat_id,
    [Parameter()]
    [switch]$nobackend = $false,
    [Parameter()]
    [string]$ExchangeVersion = 'VERSION="ExchangeOnline" AZURECLOUDTYPE="AzurePublic"',
    [Parameter()]
    [string]$is_online = "true",
    [Parameter()]
    [string]$ad_ip
)

Set-Location $PSScriptRoot
#IB: just in kase there are smb connections to Dp
Stop-Service -Name "LanmanWorkstation" -Force
Start-Service -Name "LanmanWorkstation"

#Source functions and config templates
. .\ngfunctions.ps1
. .\basedata.ps1

# Setting up self generated variables
$ipaddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address

$date = Get-Date -f yyyyMMdd_hh_mm_ss
$logfile = ".\$date`_MasterSetupWizard_log.txt"
$postgresql_user_name = "usr_$tenant_id".ToLower()
$postgresql_db_name = "db_$tenant_id".ToLower()
$postgresql_user_password = (GeneratePassword 16)
Write-Log "`r`nMaster Setup Wizard Started" $logfile -toStdOut
Write-Log "---------------------------" $logfile -toStdOut
Write-Log "Postgres User Name: $postgresql_user_name" $logfile -toStdOut
Write-Log "Postgres DB Name: $postgresql_db_name" $logfile -toStdOut
Write-Log "Postgres User Name Generated Password: $postgresql_user_password" $logfile -toStdOut
Write-Output "`r`n"
$eclients_password = GetRandomEclients


# Setting up parameters dict
$tokens_coll = @{}
#setting backend parameters to Null, to clean any default settings

$tokens_coll.date = GetTimeLdapFormat
$tokens_coll.eclients_password = $eclients_password
$tokens_coll.postgresql_db_name = $postgresql_db_name
$tokens_coll.postgresql_user_name = $postgresql_user_name
$tokens_coll.postgresql_user_password = $postgresql_user_password
$tokens_coll.eclients_password_hashed = HashForLDAP -password $eclients_password
$tokens_coll.netmail_password_hashed = HashForLDAP -password $netgovern_password
$tokens_coll.eclients_password_encrypted = ( & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-edir\InstallUtils.exe mode=enc value="$eclients_password").trim()
$tokens_coll.o365_password_encrypted = ( & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-edir\InstallUtils.exe mode=enc value="$o365_password").trim()
$tokens_coll.postgresql_server = $postgresql_server
$tokens_coll.postgresql_port = $postgresql_port
$tokens_coll.hostname = $env:COMPUTERNAME
$tokens_coll.ipaddress = $ipaddress
$tokens_coll.tenant_id = $tenant_id
$tokens_coll.ldap_server = $ldap_server
$tokens_coll.eclients_password = $eclients_password
$tokens_coll.smtp_server = $smtp_server
$tokens_coll.o365_user = $o365_user
$tokens_coll.o365_url = $o365_url
$tokens_coll.ma_notify_email = $ma_notify_email
$tokens_coll.o365_tenat_id = $o365_tenat_id
$tokens_coll.ad_ip = $ad_ip
$tokens_coll.ExchangeVersion = $ExchangeVersion
$tokens_coll.is_online = $is_online

if ($nobackend){
    $tokens_coll.o365_tenat_id = $null
    $tokens_coll.o365_user = $null
    $tokens_coll.o365_url = $null
    $tokens_coll.o365_tenat_id = $null
    $tokens_coll.ad_ip = $null
    $tokens_coll.o365_password_encrypted = $null
    $tokens_coll.ExchangeVersion = 'VERSION="Exchange2013"'
    $tokens_coll.is_online = "false"
    }

#Locations setup
$i = 0
$setlocations = $null

#Accepts 3 wrong answers
do {
$setlocations = Read-Host "Would you like to setup locations (yes/no)"
$i++
}while ($setlocations -ne "yes" -and $setlocations -ne "no" -and $i -le 2)



if ($setlocations -eq "yes"){ 
    Write-Host "You must have the following subfolders in the shared location: `r`n /store/Audit `r`n /store/Case Management `r`n /store/Case Management/Export `r`n /store/Case Management/Quarantine `r`n /store/Mail `r`n /store/Attachments"
    $unc_path = Read-Host "Enter unc path for the shared location (//path)"
    $shared_location_user = Read-Host "Enter the user that has read/write rights for the location"
    $shared_location_user_password = Read-Host "Enter pasword for the user"
    $tokens_coll.shared_location_user_password = ( & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-edir\InstallUtils.exe mode=enc value="$shared_location_user_password").trim()
    $tokens_coll.shared_location_user = $shared_location_user
    $tokens_coll.unc_path = $unc_path
}else {
    $tokens_coll.shared_location_user_password = ""
    $tokens_coll.shared_location_user = ""
    $tokens_coll.unc_path = "C:/Archive"
}


# Unix2Dos - Just in case
if ( Select-String -InputObject $edir_properties -Pattern "[^`r]`n" ) {
    $edir_properties = $edir_properties.Replace("`n", "`r`n")
}

if ( Select-String -InputObject $mdb_conf -Pattern "[^`r]`n" ) {
    $mdb_conf = $mdb_conf.Replace("`n", "`r`n")
}

if ( Select-String -InputObject $clusterconfig_xml -Pattern "[^`r]`n" ) {
    $clusterconfig_xml = $clusterconfig_xml.Replace("`n", "`r`n")
}

if ( Select-String -InputObject $base_ldif -Pattern "[^`r]`n" ) {
    $base_ldif = $base_ldif.Replace("`n", "`r`n")
}

# Replace Tokens from config templates
$edir_properties = TokenReplacement -tokenized_content $edir_properties -token_collection $tokens_coll
$mdb_conf = TokenReplacement -tokenized_content $mdb_conf -token_collection $tokens_coll
$clusterconfig_xml = TokenReplacement -tokenized_content $clusterconfig_xml -token_collection $tokens_coll
$base_ldif = TokenReplacement -tokenized_content $base_ldif -token_collection $tokens_coll

$ldif_filepath_name = ".\$tenant_id.ldif_to_encode"
Set-Content -Value $base_ldif -Path $ldif_filepath_name
$ldif_content_encoded = EncodeBase64InFile -content_to_encode ( Get-Content $ldif_filepath_name )
$ldif_filepath_name = ".\$tenant_id.ldif"
Set-Content -Value $ldif_content_encoded -Path $ldif_filepath_name


#Connectivity tests

Write-Log "Verify postgres port at $($postgresql_server):$($postgresql_port)" $logfile -toStdOut
If (Test-NetConnection $postgresql_server -Port $postgresql_port -InformationLevel Quiet) {
    Write-Log "Success`r`n" $logfile -toStdOut
} else {
    Write-Log "Cannot connecto to TCP port.  Cannot continue with setup." $logfile -toStdOut
    Exit 1
}

# Test ldap connectivity
Write-Log "Verify ldap connectivity to $ldap_server as $ldap_admin_dn" $logfile -toStdOut
$ldap_conn = TestLDAPConn -ldap_server $ldap_server -ldap_admin_dn $ldap_admin_dn -ldap_admin_password $ldap_admin_password
if ($ldap_conn -eq 0) {
    $ldap_uri = "ldap://$ldap_server"
    Write-Log "Success`r`n" $logfile -toStdOut
} else {
    $ldap_conn = TestLDAPConn -ldap_server $ldap_server -ldap_admin_dn $ldap_admin_dn -ldap_admin_password $ldap_admin_password -ssl
    if ($ldap_conn -eq 0) {
        $ldap_uri = "ldaps://$ldap_server"
        Write-Log "Success`r`n" $logfile -toStdOut
    } else {
        Write-Log "Cannot connect to ldap nor ldaps.  CAnnot continue." $logfile -toStdOut
        Exit 1
    }
}
# Setting up Postgres Client
$env:PGHOSTADDR = $postgresql_server
$env:PGUSER = $postgresql_admin_user
$env:PGPASSWORD = $postgresql_admin_password
$env:PGPORT = $postgresql_port
$postgres_client = ${env:ProgramFiles(x86)} + "\PostgreSQL\9.3\bin\psql.exe"

# Test Postgres login
Write-Log "Verify postgres login to $postgresql_server as $postgresql_admin_user" $logfile -toStdOut
$probe_query = "`"select extname from pg_extension;`""
$probe_cmd = (& $postgres_client -t -c $probe_query | Out-String).Trim()
if([string]::IsNullOrEmpty($probe_cmd)) {
    Write-Log "Cannot login to postgres as postgresql_admin_user.  Cannot continue." $logfile -toStdOut
    Exit 1
} else {
    Write-Log "Success`r`n" $logfile -toStdOut
}

# Test Postgres new DB
$probe_cmd = ""
Write-Log "Verify that postgres DB: $postgresql_db_name is not to present" $logfile -toStdOut
$probe_query = "`"select datname from pg_database where datname='$postgresql_db_name';`""
$probe_cmd = (& $postgres_client -t -c $probe_query | Out-String).Trim()
if([string]::IsNullOrEmpty($probe_cmd)) {
    Write-Log "Success`r`n" $logfile -toStdOut
} else {
    Write-Log "$postgresql_db_name already exists in $postgresql_server" $logfile -toStdOut
    Write-Log "Please delete it or check that the tenant id is not in use in the pod.  Cannot continue." $logfile -toStdOut
    Exit 1
}

# Check if user exists
$probe_cmd = ""
Write-Log "Verify that the username $postgresql_user_name does not exist in postgres" $logfile -toStdOut
$probe_query = "`"select rolname from pg_roles where rolname='$postgresql_user_name';`""
$probe_cmd = (& $postgres_client -t -c $probe_query | Out-String).Trim()
if([string]::IsNullOrEmpty($probe_cmd)) {
    Write-Log "Success`r`n" $logfile -toStdOut
} else {
    Write-Log "$postgresql_user_name already exists in $postgresql_server" $logfile -toStdOut
    Write-Log "Please delete it or check that the tenant id is not in use in the pod. Cannot continue." $logfile -toStdOut
    Exit 1
}

# Check if tenant_id exists as a subtree in LDAP
Write-Log "Check if $tenant_id exists in LDAP " $logfile -toStdOut
[System.Environment]::SetEnvironmentVariable("LDAPTLS_REQCERT","never")
$ldapsearch = "$env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe"
$base_dn = "o=netmail"
$params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200 -w ${ldap_admin_password} -H $ldap_uri -b `"${base_dn}`" `"objectclass=organization`" dn"
$ldif_orgs = Invoke-Expression "& `"$ldapsearch`" $params"
$ldif_orgs | Select-String "dn:" | foreach-object { 
    if (($_ -split 'dn: ')[1] -eq "o=$tenant_id,o=netmail") {
        Write-Log "o=$tenant_id,o=netmail already exists in LDAP" $logfile -toStdOut
        Write-Log "Please delete it or check that the tenant id is not in use in the pod. Cannot continue." $logfile -toStdOut
        Exit 1
    } 
}
Write-Log "Success`r`n" $logfile -toStdOut


#Create Tenant empty DB + User

Write-Log "Create Postgres DB" $logfile -toStdOut
Write-Log "------------------" $logfile -toStdOut
$create_new_tenant_user = "`"CREATE USER `"$postgresql_user_name`" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION CONNECTION LIMIT -1 PASSWORD `'$postgresql_user_password`';`""
$create_user_output = & $postgres_client -c $create_new_tenant_user | Out-String
Write-Log $create_user_output $logfile -toStdOut

$create_new_tenant_db = "`"CREATE DATABASE `"$postgresql_db_name`" WITH OWNER = postgres ENCODING = 'UTF8' CONNECTION LIMIT = -1;`""
$create_db_output = & $postgres_client -c $create_new_tenant_db | Out-String
Write-Log $create_db_output $logfile -toStdOut

$grant_privileges = "`"GRANT ALL ON DATABASE `"$postgresql_db_name`" TO `"$postgresql_user_name`";`""
$grant_privileges_output = & $postgres_client -c $grant_privileges | Out-String
Write-Log $grant_privileges_output $logfile -toStdOut


Write-Log "`r`nApplying Main ldif" $logfile -toStdOut
Write-Log "------------------" $logfile -toStdOut
[System.Environment]::SetEnvironmentVariable("LDAPTLS_REQCERT","never")
$ldif_output = & $env:NETMAIL_BASE_DIR\openldap\ldapadd.exe `
    -x -D $ldap_admin_dn -w $ldap_admin_password -H $ldap_uri -f $ldif_filepath_name `
    | Out-String
Write-Log $ldif_output $logfile -toStdOut

#Configure ClusterConfig.xml
Write-Log "`r`nConfigure ClusterConfig.xml" $logfile -toStdOut
Set-Content -Value $clusterconfig_xml `
    -Path ".\ClusterConfig.xml"
Copy-Item ".\ClusterConfig.xml" -Destination "$env:NETMAIL_BASE_DIR\..\Config" -Force

#Configure mdb.conf
Write-Log "`r`nConfigure mdb.conf" $logfile -toStdOut
Set-Content -Value $mdb_conf `
    -Path ".\mdb.conf"
Copy-Item ".\mdb.conf" -Destination "$env:NETMAIL_BASE_DIR\etc" -Force

# Create nodeid.cfg
Write-Log "`r`nCreate nodeid.cfg" $logfile -toStdOut
Set-Content -Value $ipaddress -Path ".\nodeid.cfg"
Copy-Item ".\nodeid.cfg" -Destination "$env:NETMAIL_BASE_DIR\..\Config" -Force

#Configure edir.properties
Write-Log "`r`nConfigure edir.properties" $logfile -toStdOut
Set-Content -Value $edir_properties `
    -Path ".\edir.properties"
Copy-Item ".\edir.properties" -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config" -Force

#Create eclients - Used a different encoding to avoid a trailing NewLine char
Set-Content -Value ([byte[]][char[]] $eclients_password) -Path "$env:NETMAIL_BASE_DIR\var\dbf\eclients.dat" -Encoding Byte

#Create solr.properties
Set-Content -Value "hosts=$($zookeeper_ip):32000/solr" -Path "$env:NETMAIL_BASE_DIR\..\Nipe\Config\solr.properties"

Write-Log "`r`nCreate New CFS Cluster" $logfile -toStdOut
Write-Log "----------------------" $logfile -toStdOut
$cfs_output = & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-ConfigureCFS.bat new $ipaddress | Out-String
Write-Log $cfs_output $logfile 
if ($?) {
    Write-Log "Success" $logfile -toStdOut
} else {
    Write-Log "Create New CFS Cluster failed.  More info in $logfile" $logfile -toStdOut
}

Write-Log "`r`nConfigure 50-indexer.conf" $logfile -toStdOut
$indexer_config_output = & $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureIndexer.bat | Out-String
Write-Log $indexer_config_output $logfile
if ($?) {
    Write-Log "Success" $logfile -toStdOut
} else {
    Write-Log "Configure 50-indexer.conf failed.  More info in $logfile" $logfile -toStdOut
}

Write-Log "`r`nConfigure 55-open.conf" $logfile -toStdOut
$maopen_config_output = & $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureMAOpen.bat | Out-String
Write-Log $maopen_config_output $logfile
if ($?) {
    Write-Log "Success" $logfile -toStdOut
} else {
    Write-Log "Configure 55-open.conf failed.  More info in $logfile" $logfile -toStdOut
}

Write-Log "`r`nConfigure 60-webadmin.conf" $logfile -toStdOut
Copy-Item "$env:NETMAIL_BASE_DIR\etc\launcher.d-available\60-webadmin.conf" -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force
if  ($?) {
    Write-Log "Success" $logfile -toStdOut
} else {
    Write-Log "`r`nConfigure 60-webadmin.conf failed." $logfile -toStdOut 
}
Write-Log "`r`nConfigure 90-netmail-snmp.conf" $logfile -toStdOut
Copy-Item "$env:NETMAIL_BASE_DIR\etc\launcher.d-available\90-netmail-snmp.conf" -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force
if ($?) {
    Write-Log "Success" $logfile -toStdOut
}
else {
    Write-Log "`r`nConfigure 90-netmail-snmp.conf failed." $logfile -toStdOut 
}

Write-Log "`r`nConfigure 91-netmail-monitor.conf" $logfile -toStdOut
Copy-Item "$env:NETMAIL_BASE_DIR\etc\launcher.d-available\91-netmail-monitor.conf" -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force
if ($?) {
    Write-Log "Success" $logfile -toStdOut
}
else {
    Write-Log "`r`nConfigure 91-netmail-monitor.conf failed." $logfile -toStdOut 
}

#Create "netmail-openldap" info doc snippet
Write-Log "`r`nCreate netmail-openldap info doc snippet" $logfile -toStdOut
$netmail_openldap_path = "$env:NETMAIL_BASE_DIR\var\docroot\info\netmail-openldap"
Set-Content -Value "{" -Path $netmail_openldap_path
Add-Content -Value "`"uri`": `"ldap://$ldap_server`:389/o=netmail?machine=$env:COMPUTERNAME&basedn=o%%3Dnetmail`"" `
    -Path $netmail_openldap_path
Add-Content -Value "{" -Path $netmail_openldap_path

#Create "netmail-archive" info doc snippet
Write-Log "`r`nCreate netmail-archive info doc snippet" $logfile -toStdOut
$netmail_archive = Get-Content "$env:NETMAIL_BASE_DIR\etc\info.json" | Out-String | `
    ConvertFrom-Json | Select-Object -ExpandProperty "netmail-archive"
$netmail_archive | Add-Member -Name "master" -Value "true" -MemberType NoteProperty
$netmail_archive | ConvertTo-Json -Compress | Set-Content -Path "$env:NETMAIL_BASE_DIR\var\docroot\info\netmail-archive"

# Unix2Dos - Just in case
if ( Select-String -InputObject $ajaj_json -Pattern "[^`r]`n" ) {
    $ajaj_json = $ajaj_json.Replace("`n", "`r`n")
}
$ajaj_json | Set-Content -Path "$env:NETMAIL_BASE_DIR\var\docroot\info\ajaj.json"

# Generate ssl certificates for apid
Write-Log "`r`nCreate ssl certificates for apid" $logfile -toStdOut
$new_certs_dir_output = New-Item -ItemType Directory -Force -Path "$env:NETMAIL_BASE_DIR\var\openldap\certs" | Out-String
Write-Log $new_certs_dir_output $logfile
Set-Content -Value "These certificates are needed for APID to start.  They have to be named openldap.* but it's not related to the actual ldap server"`
    -Path "$env:NETMAIL_BASE_DIR\var\openldap\certs\readme.txt"
$env:OPENSSL_CONF = "$env:NETMAIL_BASE_DIR\etc\openssl.cnf"
$output_openssl = & $env:NETMAIL_BASE_DIR\sbin\openssl.exe req -newkey rsa:2048 -x509 -nodes `
    -out "$env:NETMAIL_BASE_DIR\var\openldap\certs\openldap.crt" `
    -keyout "$env:NETMAIL_BASE_DIR\var\openldap\certs\openldap.key" `
    -days 3650 -subj "/CN=${ipaddress}/O=netmail/C=CA" `
    -config "$env:NETMAIL_BASE_DIR\etc\openssl.cnf"  2>&1 | Out-String 

Write-Log $output_openssl $logfile

Write-Log "`r`nAllow Local subnet traffic" $logfile -toStdOut
# Allow Local Subnet
$output_firewall_rule = New-NetFirewallRule `
    -DisplayName "NetGovern_Allow_Local_Subnet" `
    -Direction Inbound `
    -Profile 'Domain', 'Private', 'Public' `
    -Action Allow `
    -RemoteAddress LocalSubnet | Out-String
Write-Log $output_firewall_rule $logfile

Write-Log "`r`nReconfigure unused services" $logfile -toStdOut
$postgres_disable_output = & sc.exe config "postgresql-9.3" start=demand | Out-String
Write-Log $postgres_disable_output $logfile -toStdOut

#Restart NetGovern services
Write-Log "Restarting NetGovern Launcher Service" $logfile -toStdOut
Restart-Service -Name NetmailLauncherService

if ( $remote_provider_ip_address -eq "0.0.0.0" ) {
    Write-Log "Skipping Remote Provider Configuration" $logfile -toStdOut
} else {
    Write-Log "`r`nStarting Remote Provider Configuration" $logfile -toStdOut
    $dp_port = .\ConfigureDP.ps1 -rp_server_address $remote_provider_ip_address -rp_admin_user $remote_provider_admin_user -rp_admin_password $remote_provider_password -tenant_id $tenant_id
    Write-Log "Netmail search was configured to listen to port: $dp_port" $logfile -toStdOut
}
Write-Log "Script Finished.  You can login to https://$ipaddress" $logfile -toStdOut
