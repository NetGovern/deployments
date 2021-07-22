<#

.SYNOPSIS
This script should be used only in case you migrated solr7 to solr8 Index node!

Run this script from working DP (remote provider) node!!!
This script discovers the nodes all nodes for each cluseter, backup solr.properties file and replace it with a new that contains the new solr node(zookeeper).

.DESCRIPTION
It needs windows admin passwords for the nodes.
It also needs admin credentials for Ldap


.EXAMPLE
The following launches a full upgrade to all the pod:
.\PostSolr7toSolr8Migration.ps1 -windows_admin_user "Administrator" -windows_admin_password "ThePassword" `
    -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword" `
    -solr8IndexIP "1.1.1.1"
#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$windows_admin_user,
    [Parameter(Mandatory=$true)]
    [String]$windows_admin_password,
    [Parameter(Mandatory=$true)]
    [string]$ldap_admin_dn,
    [Parameter(Mandatory=$true)]
    [String]$ldap_admin_dn_password,
    [Parameter(Mandatory=$true)]
    [String]$solr8IndexIP
   )


. .\upgradeFunctions.ps1
$ldapsearch = "$env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe" 
$ldapmodify = "$env:NETMAIL_BASE_DIR\openldap\ldapmodify.exe"

Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force

$windowsAdminCredentials = getWindowsCredentials -windowsPassword $windows_admin_password -windowsUserName $windows_admin_user

#Get all nodes from ldap to update solr.properties
$ldapServer, $ldapPort = parseNipeProperties

testLdapConnectivity

$tenantsOrgDns = getTenantOrgDns

#Create a solr.properties with the new index
$solrproperties = "hosts="+$solr8IndexIP+":32000/solr"
Set-Content .\solr.properties $solrproperties

foreach ($tenantOrgDn in $tenantsOrgDns){
 Write-Host "`r`nDiscovering Archive Nodes for $tenantOrgDn"
    Write-Host "-------------------------"
    #ldap query to get Master Node
    $baseDn = "cn=Nodes,cn=GWOpenNode,cn=archiving,$tenantOrgDn"
    $tenantId = [regex]::match($tenantOrgDn, "o=(.*?),o=netmail").Groups[1].Value
    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200"
    $params += " -w ${ldap_admin_dn_password} -p ${ldapPort} -h ${ldapServer}"
    $params += " -b `"${baseDn}`" `"objectclass=maGWClusterNode`" cn maID"
    $ldif = Invoke-Expression "& `"$ldapsearch`" $params"
    
    $lines = $ldif | Select-String "Nodes, GWOpenNode, archiving,"
    $nodesforupdated = $null
    foreach ($line in $lines){
        $nodesforupdated += "$line`r`n "
    }

    Write-host "Nodes where solr.properties will be updated `r`n $nodesforupdated "

    $iplist = @()
    #Parsing IP  addresses
    ($ldif | Select-String "Nodes, GWOpenNode, archiving," -Context 0, 3) | `
        ForEach-Object {
            $iplist += ((($_.Context.PostContext | Select-String "maID:") -split 'maID: ')[1].Trim()) -replace ':\d{4,5}'  
        }
    
    
    foreach ($ip in $iplist){
        New-PSDrive -name TEMP -PSProvider FileSystem -Root "\\$ip\c$\Program Files (x86)\Messaging Architects\Nipe\Config" -Credential $windowsAdminCredentials
        Write-host "Processing IP: $ip"
        $unixdate = [int][double]::Parse((Get-Date -UFormat %s))
        #Backup the file
        Copy-Item "TEMP:\solr.properties" -Destination "TEMP:\solr.properties.$unixdate"
        Copy-Item ".\solr.properties" -Destination "TEMP:\solr.properties" -Force -Verbose
        Remove-PSDrive -Name TEMP
    }
restartArchive $iplist
}
Write-Output "`r`nScript is done."