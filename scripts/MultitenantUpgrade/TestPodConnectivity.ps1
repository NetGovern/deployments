<#

.SYNOPSIS
This script discovers the nodes in a multitenant environment and upgrades them after confirmation.

.DESCRIPTION
It needs windows and linux admin passwords for the nodes as well as the target version to which upgrade

Most of the parameters names are self explanatory.  
The option "interactive" will prompt the user to continue after displaying the discovered nodes in the pod.
The option "discoverOnly" will not run any upgrade but it will leave a json file called my-cluster-info.json in the same folder of the script location.

.EXAMPLE
.\DiscoveryAndUpgrade.ps1 -windows_admin_user "Administrator" -windows_admin_password "ThePassword" `
    -linux_admin_user netmail -linux_admin_password "ThePassword" -upgrade_version "6.3.0.1454" `
    -interactive -discoverOnly

#>

Param(
    [Parameter()]
    [string]$windows_admin_user,
    [Parameter()]
    [String]$windows_admin_password,
    [Parameter()]
    [string]$linux_admin_user,
    [Parameter()]
    [String]$linux_admin_password,
    [Parameter()]
    [string]$ldap_admin_dn,
    [Parameter()]
    [String]$ldap_admin_dn_password,
    [Parameter()]
    [switch]$interactive,
    [Parameter()]
    [switch]$Debugme,
    [Parameter()]
    [string]$upgrade_version
)

# Parameters sanity check
if ( !($windows_admin_user) ) {
    $windows_admin_user = Read-Host -Prompt "Enter a common windows user account with administrative rights on the nodes"
}

if ( !($windows_admin_password) ) {
    $secure_string_windows_admin_password = Read-Host -Prompt `
        "Enter the password for the common windows user account with administrative rights on the nodes" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_string_windows_admin_password)
    $windows_admin_password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

if ( !($linux_admin_user) ) {
    $linux_admin_user = Read-Host -Prompt "Enter a common linux user account with sudo rights on the nodes"
}

if ( !($linux_admin_password) ) {
    $secure_string_linux_admin_password = Read-Host -Prompt `
        "Enter the password for the linux user account with sudo rights on the nodes" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_string_linux_admin_password)
    $linux_admin_password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

if ( !($ldap_admin_dn) ) {
    $ldap_admin_dn = Read-Host -Prompt "Enter the DN for the ldap administration user"
}

if ( !($ldap_admin_dn_password) ) {
    $secure_string_ldap_admin_dn_password = Read-Host -Prompt `
        "Enter the password for the DN ldap administration user" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_string_ldap_admin_dn_password)
    $ldap_admin_dn_password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

# Upgrade Version verification
$available_versions = @(
        "6.3.0.1454", 
        "6.3.1.1589" 
    )
if ( !($upgrade_version) ) {
    $upgrade_version = Read-Host -Prompt "Enter the version to upgrade to"
}

Write-Output "`r`nScript started!!"

Write-Output "`r`nDiscovering Nodes in the multitenant cluster"

If ($Debugme) {
    Write-Output "`r`nwindows: $windows_admin_user, $windows_admin_password"
    Write-Output "linux: $linux_admin_user, $linux_admin_password"
    Write-Output "ldap: $ldap_admin_dn, $ldap_admin_dn_password"
}

$cluster_info = @{ 'archive' = @{} ; 'index' = @{} ; 'dp' = @{} }
$ldapsearch = "$env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe" 
$curl_exe = "$env:NETMAIL_BASE_DIR\etc\scripts\setup\curl.exe"


# Parse ldap info
$edir_properties = Get-Content "$env:NETMAIL_BASE_DIR\..\Nipe\Config\edir.properties"
$edir_host = (($edir_properties | Select-String 'edir.host=').Line -split '=', 2)[1]
$edir_port = (($edir_properties | Select-String 'edir.port=').Line -split '=', 2)[1]

# Testing LDAP Connectivity
[System.Environment]::SetEnvironmentVariable("LDAPTLS_REQCERT", "never")
$ldap_whoami = "$env:NETMAIL_BASE_DIR\openldap\ldapwhoami.exe"
$test_ldap_conn = @(
    "-vvv", 
    "-h", 
    $edir_host, 
    "-p",
    $edir_port
    "-D", 
    $ldap_admin_dn, 
    "-x", 
    "-w", 
    $ldap_admin_dn_password
)
$p = Start-Process -FilePath $ldap_whoami -ArgumentList $test_ldap_conn -Wait -PassThru
if ( $p.ExitCode -ne 0 ) {
    Write-Output "`r`nCannot connect to LDAP server, please verify credentials for $ldap_admin_dn at $($edir_host):$($edir_port)"
    Exit 1
}

#ldap query to get sub orgs (tenants)
$tenants_org_dns = @()
$params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200 -w ${ldap_admin_dn_password} -p ${edir_port} -h ${edir_host} -b `"o=netmail`" `"objectclass=organization`" dn"
$ldif_orgs = Invoke-Expression "& `"$ldapsearch`" $params"
$ldif_orgs | Select-String "dn:" | foreach-object { 
    if (($_ -split 'dn: ')[1] -match ",o=netmail") {
        $tenants_org_dns += , ($_ -split 'dn: ')[1]
    }
}

$unreachable_present = $false
Write-Output "`r`nDiscovering Archive Nodes"
Write-Output "-------------------------"
$tenants_org_dns | ForEach-Object {
    $base_dn = "cn=Nodes,cn=GWOpenNode,cn=archiving,$_"
    $tenant_id = [regex]::match($_, "o=(.*?),o=netmail").Groups[1].Value
    #ldap query
    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200 -w ${ldap_admin_dn_password} -p ${edir_port} -h ${edir_host} -b `"${base_dn}`" `"objectclass=maGWClusterNode`" cn maID"
    $ldif = Invoke-Expression "& `"$ldapsearch`" $params"
    #parse ldif results
    $a = $ldif | Select-String "Nodes, GWOpenNode, archiving," -Context 0, 3
    $a | ForEach-Object {
        $node_type = (($_.Context.PostContext | Select-String "cn:") -split 'cn: ')[1]
        if (($node_type -notmatch 'Search') -and ($node_type -notmatch 'Crawler')) {
            $archive = @{}
            $info_json = ''
            $server = @{}
            $server['tenant'] = $tenant_id
            if ($node_type -match 'Master') { $node_type = "master"}
            if ($node_type -match 'Worker') { $node_type = "worker"}
            $server['type'] = $node_type
            $ip_address = (($_.Context.PostContext | Select-String "maID:") -split 'maID: ')[1].Trim()
            Write-Output "`r`nFound: $ip_address"
            Write-Output "Attempting to contact https://${ip_address}/info to gather platform information"
            $params = '-k', '-s', "https://${ip_address}/info"
            $info_json = Invoke-Expression "& `"$curl_exe`" $params" 
            if (-not ([string]::IsNullOrEmpty($info_json))) {
                $info_hash = @{}
                $info_json = ($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }
                $server['version'] = $info_hash['netmail-archive'].version
                $server['name'] = $info_hash['netmail-platform'].name
                Write-Output "Platform information OK"
            }
            else {
                $server['version'] = "9.9.9.9"
                $server['name'] = "not_reachable"
                $unreachable_present = $true
                Write-Output "Cannot contact platform"
            }
            $archive[$ip_address] = $server
            if ($cluster_info['archive'].Count -eq 0) {
                $cluster_info['archive'] = $archive
            }
            else {
                $duplicated = $cluster_info['archive'].ContainsKey($ip_address)
                if ($duplicated) {
                    $ip_address | Out-File -Append "$PSScriptRoot\duplicated_nodes.txt"
                    $archive[$ip_address] | Out-File -Append "$PSScriptRoot\duplicated_nodes.txt"
                }
                else {
                    $cluster_info['archive'] += $archive
                }
            }
        }
    }
}
#Parse Nipe Config
$solr = @()
$index = @{}
$solr_properties = Get-Content "$env:NETMAIL_BASE_DIR\..\Nipe\Config\solr.properties"
$solr_properties = $solr_properties.Replace('hosts=', '').Replace('/solr', '')
$solr = ( $solr_properties -split ',' ) -Replace ':(.*)', ''
#Discover more solr nodes via zookeeper
Write-Output "`r`nDiscovering Index Nodes"
Write-Output "-------------------------"
$solr_nodes = @()
$solr | ForEach-Object {
    $params = '-k', '-s', "http://$($_):31000/solr/admin/collections?action=clusterstatus"
    $response_xml = [xml](Invoke-Expression "& `"$curl_exe`" $params")
    ($response_xml.response.lst | Where-Object {$_.name -eq "cluster"}).arr.str | `
        ForEach-Object { $solr_nodes += $_.split(':')[0] }
}
$solr_nodes = $solr_nodes | Select-Object -Unique
$solr_nodes | ForEach-Object {
    $info_json = ''
    $index = @{}
    $server = @{}
    Write-Output "Found: $_"
    Write-Output "Attempting to contact https://$_/info to gather platform information"
    $params = '-k', '-s', "https://$_/info"
    $info_json = Invoke-Expression "& `"$curl_exe`" $params" 
    if (-not ([string]::IsNullOrEmpty($info_json))) {
        $info_hash = @{}
        $info_json = ($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }
        $server['version'] = $info_hash['netmail-platform'].version
        $server['name'] = $info_hash['netmail-platform'].name
        Write-Output "Platform information OK"
    }
    else {
        $server['version'] = "9.9.9.9"
        $server['name'] = "not_reachable"
        $unreachable_present = $true
        Write-Output "Cannot contact platform"
    }
    $index[$_] = $server
    if ($cluster_info['index'].Count -eq 0) {
        $cluster_info['index'] = $index
    }
    else {
        $duplicated = $cluster_info['index'].ContainsKey($_)
        if ($duplicated) {
            $_ | Out-File -Append "$PSScriptRoot\duplicated_nodes.txt"
            $index[$_] | Out-File -Append "$PSScriptRoot\duplicated_nodes.txt"
        }
        else {
            $cluster_info['index'] += $index
        }
    }
}

# DP
#Discover more solr nodes via zookeeper
Write-Output "`r`nChecking my platform component (Remote Provider)"
Write-Output "----------------------------------------------------"
$dp = @{}
$ip_address = "255.255.255.255"
$server = @{}
$params = '-k', '-s', "https://localhost/info"
Write-Output "Attempting to contact https://localhost/info to gather platform information"
$info_json = Invoke-Expression "& `"$curl_exe`" $params"
if (-not ([string]::IsNullOrEmpty($info_json))) {
    $info_hash = @{}
    $info_json = ($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }
    $server['version'] = $info_hash['netmail-platform'].version
    $server['name'] = $info_hash['netmail-platform'].name
    $ip_address = $info_hash['netmail-platform'].ip
    Write-Output "Platform information OK"
}
else {
    $server['version'] = "9.9.9.9"
    $server['name'] = "not_reachable"
    $unreachable_present = $true
    Write-Output "Cannot contact platform"
}
$dp[$ip_address] = $server
$cluster_info['dp'] = $dp

ConvertTo-Json $cluster_info -Depth 5 | Set-Content "$PSScriptRoot\my-cluster-info.json"

if ( !(Test-Path "$PSScriptRoot\my-cluster-info.json" -PathType Leaf) ) {
    Write-Output "`r`nCannot access json file with discovered nodes: $PSScriptRoot\my-cluster-info.json"
    Exit 1
}

$info_json = Get-Content "$PSScriptRoot\my-cluster-info.json"
$info_hash = @{}
($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }

If ($discoverOnly) {
    Write-Output "`r`ndiscoverOnly option was selected. The discovery file is  $PSScriptRoot\my-cluster-info.json"
    Write-Output "Exiting"
    Exit 0
}

if ($interactive) {
    Write-Output "`r`n----------------------------------------------------"
    Write-Output "`r`nPlease verify the following list of discovered nodes"
    if ($unreachable_present) {
        Write-Output "The nodes with a version number of 9.9.9.9 were found"
        Write-Output "in LDAP but the IP address is unreachable."
        Write-Output "They will not be upgraded."
        Write-Output "`r`nIf they are supposed to be active, stop the script and"
        Write-Output "try again once the missing nodes are back."
    }
    Write-Output "`r`nRemote Provider:"
    Write-Output "----------------"
    Write-Output $($info_hash).dp | Format-List
    Write-Output "`r`nArchive nodes:"
    Write-Output "--------------"
    Write-Output $($info_hash).archive | Format-List
    Write-Output "`r`nIndex nodes:"
    Write-Output "------------"
    Write-Output $($info_hash).index | Format-List

    $confirmation = ""
    while (($confirmation -ne "y") -and ($confirmation -ne "n") -and ($confirmation -ne "yes") -and ($confirmation -ne "no")) {
        $confirmation = (Read-Host "Proceed?(yes/no)").ToLower()
    }
    if (($confirmation -eq "y") -or ($confirmation -eq "yes")) {
        Write-Output "`r`nContinue"
    }
    else {
        write-host "`r`nExiting"
        Exit 1
    }
}

# Vars init -  download utils

# Download utility for linux connectivity
$curl_exe = "$env:NETMAIL_BASE_DIR\etc\scripts\setup\curl.exe"
$params = '-k', '-s', '-O', "https://netgovernpkgs.blob.core.windows.net/download/klink.exe"
Invoke-Expression "& `"$curl_exe`" $params" 
$klink_exe = "$PSScriptRoot\klink.exe"

$windows_admin_password_secure_string = $windows_admin_password | ConvertTo-SecureString -AsPlainText -Force
$admin_credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windows_admin_user, $windows_admin_password_secure_string

Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force

if ( !(Test-Path "$PSScriptRoot\my-cluster-info.json" -PathType Leaf) ) {
    Write-Output "Cannot access json file with discovered nodes"
    Exit 1
}

$info_json = Get-Content "$PSScriptRoot\my-cluster-info.json"
$info_hash = @{}
($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }

# Testing OS pre requisites
Write-Output "`r`nTesting linux credentials"
$info_hash['index'].psobject.Properties | foreach-object {
    $node_ip = $_.Name
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            $klink_parameters = "-t", "-auto-store-sshkey", "-pw", `
                "${linux_admin_password}", "-l", "${linux_admin_user}", "${node_ip}", "sudo -n -l sudo"
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = ${klink_exe}
            $pinfo.RedirectStandardError = $true
            $pinfo.RedirectStandardOutput = $true
            $pinfo.UseShellExecute = $false
            $pinfo.Arguments = $klink_parameters
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null
            if ( ! $p.WaitForExit(15000) ) {
                Write-Output "${klink_exe} did not exit after 15s.  Killing process"
                $p.kill()
            }
            $stdout = $p.StandardOutput.ReadToEnd()
            if ($p.ExitCode -eq 0) {
                if ($stdout -match "/bin/sudo") { 
                    Write-Output "User: ${linux_admin_user} is able to connect to $node_ip and has sudo rights"
                } else {
                    Write-Output "Linux credentials pre-requisites not met.  Exiting script."
                    Write-Output "Please verify that the user ${linux_admin_user} can login to $node_ip and has sudo rights"
                    Exit 1
                }
            } else {
                Write-Output "Cannot connect to $node_ip with user: ${linux_admin_user}"
                Exit 1
            }
        }
    }
}
Write-Output "`r`nTesting Windows credentials"
$info_hash['archive'].psobject.Properties | foreach-object {
    $node_ip = $_.Name
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            $testSession = New-PSSession -Computer $node_ip -Credential $admin_credentials -ErrorAction SilentlyContinue
            if (-not($testSession)) {
                Write-Output "Windows credentials pre-requisites not met.  Exiting script."
                Write-Output "Please verify that the user ${windows_admin_user} can login to $node_ip as administrator"
                Exit 1
            }
            else {
                Write-Output "User: ${windows_admin_user} is able to connect to $node_ip successfully"
                Remove-PSSession $testSession
            }
        }
    }
}

Write-Output "`r`n---------------"
Write-Output "Script Finished"
