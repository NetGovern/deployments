# Fix Master Node Entry 
. "$PSScriptRoot\ngfunctions.ps1"
$ipaddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address
$ldap_conn = ParseEdirProperties "$env:NETMAIL_BASE_DIR\..\Nipe\Config\edir.properties"

$MasterNode = (& $env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe `
        -h $($ldap_conn.host) -p $($ldap_conn.port) -b "$($ldap_conn.tenant_id),o=netmail" -o ldif-wrap=no -D "$($ldap_conn.logindn)" -w $($ldap_conn.loginpwdclear) "(objectclass=maGWClusterNode)")
$dn_to_delete = (($MasterNode | Select-String "dn:*").Line -Split 'cn=', 2)[1]

& $env:NETMAIL_BASE_DIR\openldap\ldapdelete.exe `
    -h $($ldap_conn.host) -p $($ldap_conn.port) -D "$($ldap_conn.logindn)" -w $($ldap_conn.loginpwdclear) "cn=$dn_to_delete"

$new_cn = "Default Master($ipaddress)"
@"
dn: cn=$new_cn,cn=Nodes,cn=GWOpenNode,$($ldap_conn.edir_container)
description: Master Node
objectClass: maGWClusterNode
cn: $new_cn
maID: $ipaddress

"@ | & $env:NETMAIL_BASE_DIR\openldap\ldapmodify.exe `
    -a -x -h $($ldap_conn.host) -p $($ldap_conn.port) -D "$($ldap_conn.logindn)" -w $($ldap_conn.loginpwdclear)

$db_conn_str = Get-Content "$PSScriptRoot\backup\db_conn_str.ldif"
$db_conn_str | & $env:NETMAIL_BASE_DIR\openldap\ldapmodify.exe `
    -h $($ldap_conn.host) -p $($ldap_conn.port) -D "$($ldap_conn.logindn)" -w $($ldap_conn.loginpwdclear)