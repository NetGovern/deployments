<#

.SYNOPSIS
This script configures the Archive Master in a multi tenant architecture

.DESCRIPTION
The script should run from an image with the pre-requisites and netmail installed

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
    -netmail_password 'NetmailPassword' `
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
    [string]$postgresql_port,
    [Parameter()]
    [string]$postgresql_admin_user,
    [Parameter()]
    [string]$postgresql_admin_password,
    [Parameter()]
    [string]$tenant_id,
    [Parameter()]
    [string]$netmail_password,
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
    [string]$remote_provider_password
)

Set-Location $PSScriptRoot

#Source functions and config templates
. .\ngfunctions.ps1
. .\basedata.ps1

# Setting up self generated variables
$ipaddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address

$date = Get-Date -f yyyyMMdd_hh_mm_ss
$logfile = ".\$date`_MasterSetupWizard_log.txt"
$postgresql_user_password = (GeneratePassword 8)
$eclients_password = GetRandomEclients
$postgresql_user_name = "usr_$tenant_id".ToLower()
$postgresql_db_name = $($tenant_id).ToLower()

# Setting up parameters dict
$tokens_coll = @{}

$tokens_coll.date = GetTimeLdapFormat
$tokens_coll.eclients_password = $eclients_password
$tokens_coll.postgresql_db_name = $postgresql_db_name
$tokens_coll.postgresql_user_name = $postgresql_user_name
$tokens_coll.postgresql_user_password = $postgresql_user_password
$tokens_coll.eclients_password_hashed = HashForLDAP -password $eclients_password
$tokens_coll.netmail_password_hashed = HashForLDAP -password $netmail_password
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

#Apply LDIF to LDAP
Write-Log "Applying Main ldif" $logfile 
[System.Environment]::SetEnvironmentVariable("LDAPTLS_REQCERT","never")
$ldif_output = & $env:NETMAIL_BASE_DIR\openldap\ldapadd.exe `
    -x -D $ldap_admin_dn -w $ldap_admin_password -H ldaps://$ldap_server -f $ldif_filepath_name `
    | Out-String
Write-Log $ldif_output $logfile

#Create Tenant empty DB
$env:PGHOSTADDR = $postgresql_server
$env:PGUSER = $postgresql_admin_user
$env:PGPASSWORD = $postgresql_admin_password
$env:PGPORT = $postgresql_port
$postgres_client = ${env:ProgramFiles(x86)} + "\PostgreSQL\9.3\bin\psql.exe"

Write-Log "Create Postgres DB" $logfile
$create_new_tenant_user = "`"CREATE USER `"$postgresql_user_name`" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION CONNECTION LIMIT -1 PASSWORD `'$postgresql_user_password`';`""
$create_user_output = & $postgres_client -c $create_new_tenant_user | Out-String
Write-Log $create_user_output $logfile

$create_new_tenant_db = "`"CREATE DATABASE `"$postgresql_db_name`" WITH OWNER = postgres ENCODING = 'UTF8' CONNECTION LIMIT = -1;`""
$create_db_output = & $postgres_client -c $create_new_tenant_db | Out-String
Write-Log $create_db_output $logfile

$grant_privileges = "`"GRANT ALL ON DATABASE `"$postgresql_db_name`" TO `"$postgresql_user_name`";`""
$grant_privileges_output = & $postgres_client -c $grant_privileges | Out-String
Write-Log $grant_privileges_output $logfile

#Configure ClusterConfig.xml
Set-Content -Value $clusterconfig_xml `
    -Path ".\ClusterConfig.xml"
Copy-Item ".\ClusterConfig.xml" -Destination "$env:NETMAIL_BASE_DIR\..\Config" -Force

#Configure mdb.conf
Set-Content -Value $mdb_conf `
    -Path ".\mdb.conf"
Copy-Item ".\mdb.conf" -Destination "$env:NETMAIL_BASE_DIR\etc" -Force

# Create nodeid.cfg
Set-Content -Value $ipaddress -Path ".\nodeid.cfg"
Copy-Item ".\nodeid.cfg" -Destination "$env:NETMAIL_BASE_DIR\..\Config" -Force

#Configure edir.properties
Set-Content -Value $edir_properties `
    -Path ".\edir.properties"
Copy-Item ".\edir.properties" -Destination "$env:NETMAIL_BASE_DIR\..\Nipe\Config" -Force

#Create eclients - Used a different encoding to avoid a trailing NewLine char
Set-Content -Value ([byte[]][char[]] $eclients_password) -Path "$env:NETMAIL_BASE_DIR\var\dbf\eclients.dat" -Encoding Byte

#Create solr.properties
Set-Content -Value "hosts=$($zookeeper_ip):3200/solr" -Path "$env:NETMAIL_BASE_DIR\..\Nipe\Config\solr.properties"

Write-Log "Create New CFS Cluster" $logfile
$cfs_output = & $env:NETMAIL_BASE_DIR\etc\scripts\setup\Win-ConfigureCFS.bat new $ipaddress | Out-String
Write-Log $cfs_output $logfile

Write-Log "Configure 50-indexer.conf" $logfile
$indexer_config_output = & $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureIndexer.bat | Out-String
Write-Log $indexer_config_output $logfile

Write-Log "Configure 55-open.conf" $logfile
$maopen_config_output = & $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureMAOpen.bat | Out-String
Write-Log $maopen_config_output $logfile

Write-Log "Configure 60-webadmin.conf" $logfile
Copy-Item "$env:NETMAIL_BASE_DIR\etc\launcher.d-available\60-webadmin.conf" -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force

Write-Log "Configure 90-netmail-snmp.conf" $logfile
Copy-Item "$env:NETMAIL_BASE_DIR\etc\launcher.d-available\90-netmail-snmp.conf" -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force

Write-Log "Configure 91-netmail-monitor.conf" $logfile
Copy-Item "$env:NETMAIL_BASE_DIR\etc\launcher.d-available\91-netmail-monitor.conf" -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force


#Create "netmail-openldap" info doc snippet
$netmail_openldap_path = "$env:NETMAIL_BASE_DIR\var\docroot\info\netmail-openldap"
Set-Content -Value "{" -Path $netmail_openldap_path
Add-Content -Value "`"uri`": `"ldap://$ldap_server`:389/o=netmail?machine=$env:COMPUTERNAME&basedn=o%%3Dnetmail`"" `
    -Path $netmail_openldap_path
Add-Content -Value "{" -Path $netmail_openldap_path

#Create "netmail-archive" info doc snippet
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

Write-Log "Reconfigure unused services" $logfile
$postgres_disable_output = & sc.exe config "postgresql-9.3" start=demand | Out-String
Write-Log $postgres_disable_output $logfile

#Restart Netmail services
Write-Log "Restarting Netmail Launcher Service" $logfile
Restart-Service -Name NetmailLauncherService
Write-Log "Finished" $logfile

if ( $remote_provider_ip_address -eq "0.0.0.0" ) {
    Write-Log "Skipping Remote Provider Configuration" $logfile
} else {
    Invoke-Expression ".\ConfigureDP.ps1 -rp_server_address $remote_provider_ip_address -rp_admin_user $remote_provider_admin_user -rp_admin_password $remote_provider_password -tenant_id $tenant_id"
}
