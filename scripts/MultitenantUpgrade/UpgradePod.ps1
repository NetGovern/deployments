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
    [string]$upgrade_version,
    [Parameter()]
    [switch]$interactive,
    [Parameter()]
    [switch]$Debugme,
    [Parameter()]
    [switch]$discoverOnly
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

if ($available_versions -contains $upgrade_version) {
    Write-Output "`r`nVersion $upgrade_version supported"
} else {
    Write-Output "`r`nVersion: $upgrade_version not supported."
    Exit 1
}

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
            Write-Output "Found: $ip_address"
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
        Write-Output "`r`nContinue to Upgrade"
    }
    else {
        write-host "`r`nExiting"
        Exit 1
    }
}

# Vars init -  download utils
$install_msi = {
    function Unzip {
        Param(
            [Parameter(Mandatory = $True)]
            [string]$path_to_zip,
            [Parameter(Mandatory = $True)]
            [string]$target_dir
        )
        if ( $PSVersionTable.PSVersion.Major -eq 4) {
            [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$path_to_zip", "$target_dir")
        }
        if ( $PSVersionTable.PSVersion.Major -ge 5) {
            Expand-Archive -LiteralPath "$path_to_zip" -DestinationPath "$target_dir"
        }
    }

    # Checking  PSH Version
    if ( $PSVersionTable.PSVersion.Major -lt 4 ) {
        Write-Output "Powershell version not supported: $($PSVersionTable.PSVersion.Major)"
    }

    Remove-Item "$env:TEMP\NetGovern" -Force -Recurse -ErrorAction Ignore
    Unzip -path_to_zip "C:\Program Files (x86)\Messaging Architects\installer\NetGovern.zip" -target_dir "$env:TEMP"

    # Launch Install.bat
    $path2Installbat = "$env:TEMP\NetGovern\install.bat"
    $version = ((Get-Content $path2Installbat | Select-String "Update.exe version") -split "Update.exe version=")[1].Trim()
    Write-Output "Upgrading to version: $version"
    $InstallNetGovernArgument = "/c " + $path2Installbat
    $InstallNetGovernWorkingDir = "$env:TEMP\NetGovern"
    try {
        Start-Process cmd -ArgumentList $InstallNetGovernArgument -WorkingDirectory $InstallNetGovernWorkingDir
    }
    Catch {
        Write-Output "Cannot launch install.bat"
        Exit 1
    }

    $logFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    $Timer = 0
    $TimerLimit = 600
    $TimerIncrement = 10
    while ((-Not $logFilesPath) -And ($Timer -lt $TimerLimit)) {
        Write-Output "Waiting for the upgrade process to start"
        Start-Sleep $TimerIncrement
        $Timer = $Timer + $TimerIncrement
        $logFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    }
    If ($Timer -ge $TimerLimit) {
        Write-Output "NetGovern installation (install.bat) timed out to create Log Files folder ($TimerLimit seconds)"
        Exit 1
    }

    $netmailLogFile = "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    $Finished = (Get-Content $netmailLogFile | Select-String "Installation success or error status: 0" -ErrorAction Ignore)
    $Timer = 0
    $TimerLimit = 1800
    $TimerIncrement = 10
    while ((-Not $Finished) -And ($Timer -lt $TimerLimit)) {
        Write-Output "NetGovern installing, please wait"
        Get-Content $netmailLogFile -Tail 2
        Start-Sleep $TimerIncrement
        $Timer = $Timer + $TimerIncrement
        $Finished = (Get-Content $netmailLogFile | Select-String "Installation success or error status: 0" -ErrorAction Ignore)
    }
    If ($Timer -ge $TimerLimit) {
        Write-Output "NetGovern installation (install.bat) timed out ($TimerLimit seconds)"
        Exit 1
    }
    Write-Output "-----------------------------"
    Write-Output "NetGovern Installation Finished"
}
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

# Download Archive Installer
$url = "https://netgovernpkgs.blob.core.windows.net/download/NetGovern$($upgrade_version).zip"
$curl_download_file_path = "`"$env:NETMAIL_BASE_DIR\..\Installer\NetGovern.zip`""
$downloaded_file_path = "$env:NETMAIL_BASE_DIR\..\Installer\NetGovern.zip"
$params = '-k', '-o', $curl_download_file_path , $url
if ( ! (test-path -pathtype container "$env:NETMAIL_BASE_DIR\..\installer") ) {
    New-Item -Path "$env:NETMAIL_BASE_DIR\..\" -Name "installer" -ItemType "directory" | Out-Null
}
Write-Output "`r`nDownloading Upgrade package"
Invoke-Expression "& `"$curl_exe`" $params"

$upgrade_me = $false
$jobs = @()

$info_hash['index'].psobject.Properties | foreach-object {
    $node_ip = $_.Name
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            $klink_parameters = "-t", "-auto-store-sshkey", "-pw", `
                "${linux_admin_password}", "-l", "${linux_admin_user}", "${node_ip}", `
                "`"wget -P /tmp https://bitbucket.netmail.com/projects/PUB/repos/deployments/raw/scripts/upgrade_rpms.sh && chmod +x /tmp/upgrade_rpms.sh && sudo /tmp/upgrade_rpms.sh -v ${upgrade_version} -i && sudo systemctl restart netmail`""
            $install_rpms_command = "& ${klink_exe} ${klink_parameters} 2>`$null"
            $install_index = [Scriptblock]::Create($install_rpms_command)
            $output_file_name = "Index-$($node_ip)-$(Get-Date -f "MMddhhmmss").txt"
            Write-Output "`r`nStarting Index upgrade from $($_.Value) to $upgrade_version"
            try {
                Invoke-Command -ScriptBlock $install_index | Out-File $output_file_name
            }
            catch {
                Write-Output "`r`nCannot start index upgrade at $node_ip"
                Exit 1
            }
            Write-Output "Upgrade finished @ $node_ip"
        }
        if ( $($_.Name) -eq "version" -and $($_.Value) -ge $upgrade_version ) {
            Write-Output "`r`nIndex version is $($_.Value) >= $upgrade_version)"
        }
    }
}
$info_hash['dp'].psobject.Properties | foreach-object {
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            $chars = [Char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
            $randomstr = (1..5 | ForEach-Object {'{0:X}' -f (Get-Random -InputObject $chars ) }) -join ''
            $current_version = $($_.Value)
            $upgrade_me = $True
            Write-Output "`r`nStarting DP upgrade"
            Stop-Service NetmailLauncherService
            Write-Output "Backing up existing DP folders to $($env:NETMAIL_BASE_DIR)\..\bkp_dp_$($randomstr)_$($current_version)"
            (New-Item -Path "$($env:NETMAIL_BASE_DIR)\.." -Name "bkp_dp_$($randomstr)_$($current_version)" -ItemType "directory") | Out-Null
            $dp_folders = (Get-ChildItem -Path "$($env:NETMAIL_BASE_DIR)\.." -Directory | Where-Object {$_.FullName -match "RemoteProvider_"})
            $backup_ok = $true
            foreach ($folder in $dp_folders) { 
                Copy-Item -Path "$($folder.FullName)" -Recurse -Destination "$($env:NETMAIL_BASE_DIR)\..\bkp_dp_$($randomstr)_$($current_version)"
                if (!($?)) {
                    Write-Output "`r`nCannot backup existing DP Folders, please run DP upgrade manually"
                    $backup_ok = $false
                }
            }
            if ($backup_ok) { 
                Write-Output "`r`nUpgrading NetGovern locally"
                Invoke-Command -ScriptBlock $install_msi | Out-File "remoteProviderNetGovernInstallLog.txt"
                Write-Output "Local Upgrade finished"
                Write-Output "`r`nUpgrading dp folders:"
                foreach ($folder in $dp_folders) {
                    if ($folder.Name -ne "RemoteProvider") {
                        Write-Output "$($folder.Name)"
                        Copy-Item -Path "$($env:NETMAIL_BASE_DIR)\..\RemoteProvider" `
                            -Destination "$($env:NETMAIL_BASE_DIR)\..\$($folder.Name)" `
                            -Exclude @("xgwxmlv.cfg", "jetty-ssl.xml") -Force -Recurse
                    }
                }
                Write-Output "`r`nRemote Provider Upgrade finished"
            }
        }
    }
}
Write-Output "`r`nStarting Archive Nodes upgrade"
Write-Output "------------------------------"
$archive_nodes = @()
$info_hash['archive'].psobject.Properties | foreach-object {
    $node_ip = $_.Name
    $_.Value.psobject.properties | ForEach-Object {
        if ( $($_.Name) -eq "version" -and $($_.Value) -lt $upgrade_version ) {
            (New-PSDrive -name TEMP -PSProvider FileSystem -Root "\\$node_ip\c$\Program Files (x86)\Messaging Architects" -Credential $admin_credentials) | Out-Null
            if ( ! (test-path -pathtype container "TEMP:\installer") ) {
                (New-Item -Path "TEMP:\" -Name "installer" -ItemType "directory") | Out-Null
            }
            Write-Output "`r`nCopying installer to $node_ip"
            Get-ChildItem $downloaded_file_path | Copy-Item -Destination "TEMP:\installer"
            Remove-PSDrive -Name TEMP
            $job_name = "JobAt$($node_ip)-$(Get-Date -f "MMddhhmmss")"
            Write-Output "Starting Archive upgrade job at $node_ip"
            (Invoke-Command -ScriptBlock $install_msi -ComputerName $node_ip -Credential $admin_credentials -AsJob -JobName $job_name) | Out-Null
            if ($?) { 
                $jobs += $job_name
                $archive_nodes += $node_ip
            }
            else { Write-output "`r`nJob could not be launched at $node_ip, please run upgrade manually" }
        }
    }
}

#Checking jobs status
$Timer = 0
$TimerLimit = 3600
$TimerIncrement = 10
$jobs_left = $jobs.Count
$progress_bar = "."
Write-Output "`r`nWaiting for Jobs to finish"
Get-Job -Name JobAt*
while (($jobs_left -gt 0) -And ($Timer -lt $TimerLimit)) {
    $jobs_left = $jobs.Count
    if ( ($Timer % 180) -eq 0 ) {
        Write-Output "`r`nPlease wait for the remote and background jobs to finish..."
        Get-Job -Name $jobs | Select-Object Name, State, Location
        $progress_bar = ""
    }
    Start-Sleep $TimerIncrement
    Write-Host $progress_bar -NoNewline
    $Timer = $Timer + $TimerIncrement
    $progress_bar += "."
    ForEach ($job_name in $jobs) {
        $job_state = (get-job -Name $job_name).JobStateInfo.State
        if ($job_state -eq "Completed") {
            $jobs_left -= 1 
        }
        get-job -Name $job_name | Receive-Job | Out-File -Append "$($job_name).txt"
    }    
}
If ($Timer -ge $TimerLimit) {
    Write-Output "`r`nRemote upgrades timed out after $TimerLimit seconds)"
}
else {
    Write-Output "---------------------------------------"
    Write-Output "`r`nAll Remote and background jobs finished"
}

foreach ($archive_node_to_be_started in $archive_nodes) {
    Write-Output "`r`nStarting Launcher @ $archive_node_to_be_started"
    try {
        Invoke-Command -ScriptBlock { Start-Service NetmailLauncherService } -ComputerName $archive_node_to_be_started -Credential $admin_credentials
    }
    catch {
        Write-Output "`r`nCannot start Launcher Service at $archive_node_to_be_started"
    }
}

if ($upgrade_me) {
    Write-Output "`r`nStarting DP Service"
    Start-Service NetmailLauncherService
}

Write-Output "`r`n---------------"
Write-Output "Script Finished"
