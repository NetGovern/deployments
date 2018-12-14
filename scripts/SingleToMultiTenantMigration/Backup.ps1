. "$PSScriptRoot\ngfunctions.ps1"
(New-Item -Path "$PSScriptRoot" -Name "backup" -ItemType "directory") | Out-Null

$ldap_conn = ParseEdirProperties "$env:NETMAIL_BASE_DIR\..\Nipe\Config\edir.properties"

#Taking full backup
$full_backup = (& $env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe `
        -h $($ldap_conn.host) -p $($ldap_conn.port) -b "o=$($ldap_conn.tenant_id),o=netmail" -o ldif-wrap=no -D "$($ldap_conn.logindn)" -w $($ldap_conn.loginpwdclear))
$full_backup | Out-File "$PSScriptRoot\backup\full_backup.ldif" -Encoding ascii

#Backing up Postgres connection string
$db_conn_str = (& $env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe `
        -h $($ldap_conn.host) -p $($ldap_conn.port) -b "o=$($ldap_conn.tenant_id),o=netmail" -o ldif-wrap=no -D "$($ldap_conn.logindn)" -w $($ldap_conn.loginpwdclear) "(objectclass=maGWOpenNode)" maReportCnnString maLogCnnString)
$dn_to_modify = ($db_conn_str | Select-String "dn:*").Line
$maReportCnnString = "Driver=$((($db_conn_str | Select-String 'maReportCnnString:').Line -Split 'Driver=',2)[1])"
$maLogCnnString = "Driver=$((($db_conn_str | Select-String 'maReportCnnString:').Line -Split 'Driver=',2)[1])"
@"
$dn_to_modify
changetype: modify
replace: maReportCnnString
maReportCnnString: $maReportCnnString
-
replace: maLogCnnString
maLogCnnString: $maLogCnnString

"@ | Out-File "$PSScriptRoot\backup\db_conn_str.ldif" -Encoding ascii

Copy-Item -Path "$env:NETMAIL_BASE_DIR\..\Config\clusterConfig.xml" `
    -Destination "$PSScriptRoot\backup\" -Force