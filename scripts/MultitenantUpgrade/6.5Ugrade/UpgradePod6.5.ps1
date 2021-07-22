<#

.SYNOPSIS
Run this script from working DP (remote provider) node!!!
This script discovers the nodes in a multitenant environment and upgrades them after confirmation.

.DESCRIPTION
It needs windows and linux admin passwords for the nodes as well as the target version to which upgrade
It also needs admin credentials for Ldap

Most of the parameters names are self explanatory.  Some clarification below:

The option "unattended" will skip prompting the user to continue after displaying the discovered nodes in the pod.
The option "-upgradeIndex $false" will skip index upgrade
The option "-upgradeLdap $false" will skip ldap upgrade
The option "-upgradeRP $false" will skip the Remote Provider upgrade
The option "-upgradeArchive $false" will skip master/worker nodes upgrade.
The option "-skip_wrong_creds" will continue with the upgrade even if some of the nodes' credentials are not correct.
The option "-test_connectiviy" will discover all the nodes and test the credentials.
The option "-rpm_debug" will search for _debug packages (only applicable to RPMs)
The parameter "-manifest_url" is used to provide the manifest URL used by PLUS


.EXAMPLE
The following launches a full upgrade to all the pod:
.\UpgradePod.ps1 -windows_admin_user "Administrator" -windows_admin_password "ThePassword" `
    -linux_admin_user netmail -linux_admin_password "ThePassword" -upgrade_version "6.3.0.1454" `
    -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword" `
    -manifest_url "http://plus-server/uuid"

Same as above but it will prompt for passwords:
.\UpgradePod.ps1 -upgrade_version "6.5.0.1454"

The following options will upgrade only the Remote Provider server:
.\UpgradePod.ps1 -upgradeIndex $false -upgradeArchive $false -upgradeLdap $false -upgrade_version "6.5.0.1454"

The below will only test for connectivity (it tries to log in to each discovered node):
.\UpgradePod.ps1 -test_connectivity -ldap_admin_dn "cn=netmail,cn=system,o=netmail" -ldap_admin_dn_password "mypassword"

#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$windows_admin_user,
    [Parameter()]
    [String]$windows_admin_password,
    [Parameter(Mandatory=$true)]
    [string]$linux_admin_user,
    [Parameter()]
    [String]$linux_admin_password,
    [Parameter(Mandatory=$true)]
    [string]$ldap_admin_dn,
    [Parameter()]
    [String]$ldap_admin_dn_password,
    [Parameter(Mandatory=$true)]
    [string]$postgresql_admin_password,
    [Parameter()]
    [string]$upgrade_version,
    [Parameter()]
    [switch]$unattended,
    [Parameter()]
    [switch]$upgradeIndex = $true,
    [Parameter()]
    [switch]$upgradeArchive = $true,
    [Parameter()]
    [switch]$upgradeLdap = $true,
    [Parameter()]
    [switch]$upgradeRP = $true,
    [Parameter()]
    [switch]$upgradeCrawler = $true,
    [Parameter()]
    [switch]$skip_wrong_creds,
    [Parameter()]
    [switch]$test_connectivity_only,
    [Parameter()]
    [string]$manifest_url,
    [Parameter()]
    [switch]$rpm_debug
)

# Main
Write-Output "`r`nScript started!"

# Vars, functions, settings
$progressPreference = 'silentlyContinue'
Set-Location $PSScriptRoot
. .\upgradeFunctions.ps1
$clusterInfo = @{ 'archive' = @{} ; 'index' = @{} ; 'dp' = @{} ; 'ldap' = @{} ; 'crawler' = @{}}
$ldapsearch = "$env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe" 
$curlExe = "$env:NETMAIL_BASE_DIR\etc\scripts\setup\curl.exe"
$klinkExe = "$PSScriptRoot\klink.exe"
$kscpExe = "$PSScriptRoot\kscp.exe"
$TEMPDIR = "C:\Users\ADMINI~1\AppData\Local\Temp"
$remoteTEMP = $TEMPDIR.Substring(3,$TEMPDIR.Length-3)
$rpIpAddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address.ToString()
$nodemsi = "$PSScriptRoot\node-v14.11.0-x86.msi" #nodejs version to update. Must be in the current folder before you start the script 
$ldapmodify = "$env:NETMAIL_BASE_DIR\openldap\ldapmodify.exe"

Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force

# Now it starts

parametersSanityCheck

$windowsAdminCredentials = getWindowsCredentials -windowsPassword $windows_admin_password -windowsUserName $windows_admin_user

# Get Packages from NSSM
if (!$test_connectivity_only) {
    if ($rpm_debug) {
        $packagesToInstall = parseVersion -version $upgrade_version -manifestUrl $manifest_url -rpmDebug
    } else {
        $packagesToInstall = parseVersion -version $upgrade_version -manifestUrl $manifest_url
    }

    $packagesToInstall.Keys | ForEach-Object {
        Write-Host "Package name: $_"
        Write-Host "Package FileName: $($packagesToInstall[$_].filename)"
        Write-Host "Package URL: $($packagesToInstall[$_].url)"
    }
    if ($packagesToInstall.Keys.Count -ne 3) {
        Write-Output "`r`nExpecting 3 packages, found $($packagesToInstall.Keys.Count)"
        Exit 1
    }
}

Write-Output "`r`nDiscovering Nodes in the multitenant cluster"
$ldapServer, $ldapPort = parseNipeProperties
testLdapConnectivity

$tenantsOrgDns = getTenantOrgDns
$tenantsOrgDns | ForEach-Object {
    $clusterInfo['archive'] += discoverArchiveNodes -tenantOrgDn $_ -windowsAdminCredentials $windowsAdminCredentials
}
$clusterInfo['index'] = discoverSolrNodes
$clusterInfo['dp'] = getRpPlatformDetails
$clusterInfo['ldap'] = getLdapPlatformDetails
$tenantsOrgDns | ForEach-Object {
    $clusterInfo['crawler'] += discoverCrawlerNodes -tenantOrgDn $_ -windowsAdminCredentials $windowsAdminCredentials
}
$current_build = $clusterInfo['dp'].$rpIpAddress.version
# Dump file for info/troubleshooting purposes
ConvertTo-Json $clusterInfo -Depth 5 | Set-Content "$PSScriptRoot\my-cluster-info.json"

displayInfo -cluster $clusterInfo

confirmInfo -unattended $unattended

downloadLinuxTools

$OKCreds = testCredentials

if ($test_connectivity_only) { 
    Write-Output "Script Finished - Test Connectivity only option used"
    Exit 0
}

if ($upgradeRP) {
    Write-Output "`r`nProcessing Remote Provider node"
    Write-Output "-------------------------------"
    if ( $clusterInfo['dp'].$rpIpAddress.version -lt $upgrade_version ) {
        downloadMSI -url $packagesToInstall['netmail'].url `
            -filename $packagesToInstall['netmail'].filename `
            -destinationFolder $TEMPDIR\installer_$($upgrade_version)
        $chars = [Char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
        $randomstr = (1..5 | ForEach-Object { '{0:X}' -f (Get-Random -InputObject $chars ) }) -join ''
        $currentVersion = $clusterInfo['dp'].$rpIpAddress.version
        Invoke-Command -ScriptBlock $installMsiScriptBlock -ComputerName localhost
        .\UpgradeDPMultitenantFolders.ps1 -backup_folder "bkp_dp_$($randomstr)_$($currentVersion)"
        #Copy nodejs if 6.5 and if exists, if upgrading to 6.5 and current version is not 6.5
        if ($upgrade_version.StartsWith(6.5) -and !($clusterInfo['dp'].$rpIpAddress.version.StartsWith(6.5))){
            if (!(Test-Path $nodemsi -PathType leaf)){
                 Write-Host "Installation package is missing. Downlowad node-v14.11.0-x86.msi and install it manually on each updated node."
                } else{
                      $batcommands = "@echo off `r`n"
                      $batcommands += "`r`nmsiexec.exe /i "+"$TEMPDIR\installer_$($upgrade_version)\node-v14.11.0-x86.msi"+" /QN /L*V "+'"'+"$TEMPDIR\installer_$($upgrade_version)\msilog.log"+'"'
                      New-item -Path . -Name "installnode.bat"-ItemType "file" -Value $batcommands -Force |Out-Null
                      Copy-Item $nodemsi -Destination "$TEMPDIR\installer_$upgrade_version\" -Verbose
                      Copy-Item ".\installnode.bat" -Destination "$TEMPDIR\installer_$upgrade_version\" -Verbose
                      #update nodejs
                      $ipAddress = (Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.status -ne "Disconnected"}).IPv4Address.IPAddress
                      launchNodeJSUpgrade $ipAddress
                          }
                    }
    restartArchive -archiveNodes $ipAddress
      
    }
    else {
        Write-Output "$rpIpAddress version already at: $($clusterInfo['dp'].$rpIpAddress.version)"
    }
}

#IB:schema update added to this script and condition if we update 6.4 or 6.5
if ($upgradeIndex) {
    Write-Output "`r`nProcessing index nodes"
    Write-Output "----------------------"
        $clusterInfo['index'].Keys | ForEach-Object {
        #checking if we upgrade to 6.5 or 6.4
        if (!($upgrade_version.StartsWith(6.5))){ 
                #proceed 6.4 upgrade 
            if ( $clusterInfo['index'].$_.version -lt $upgrade_version ) {
                if ($OKCreds -contains $_) {
                       Write-Output "Updating index"
                    launchLinuxUpgrade -nodeType "index" -nodeIp $_
                } else {
                    Write-Output "Credentials not working for this node"
                    Write-Output "Please upgrade manually"
                }

            } else {
                Write-Output "$_ version already at: $($clusterInfo['index'].$_.version)"
                }
            
        } else {
               #Proceed upgrade to 6.5
            if ($OKCreds -contains $_) {
                                            #if the index is at 6.5 and is lower than what we want to upgrade
                                        if ($clusterInfo['index'].$_.version.StartsWith(6.5) -and $clusterInfo['index'].$_.version.Split("-")[0] -lt $upgrade_version){
							                    Write-Output "Updating index"
							                    launchLinuxUpgrade -nodeType "index" -nodeIp $_
						                 } else { 
                                                    #if the index is at 6.5 but version not lower
                    								if ($clusterInfo['index'].$_.version.StartsWith(6.5) -and !($clusterInfo['index'].$_.version.Split("-")[0] -lt $upgrade_version)){ 
									                        Write-Output "$_ version already at: $($clusterInfo['index'].$_.version)"
								                    } else {
                                                            #if index is not at 6.5 only schema update
                                                            Write-Output "Updating only schema on $_"
                                                            Write-Output "Please please check the schema version http://$_" + ':31000/solr/admin/zookeeper?detail=true&path=%2Fconfigs%2Fma%2Fschema.xml'
                                                            Write-Output "At the bottom, netmailSchemaVersion must be higher than 1, if not, update manually" 
                                                            launchLinuxSchemaUpgrade -nodeType "index" -nodeIp $_
                                                      }
                                                }

                   
                } else {
                    Write-Output "Credentials not working for this node"
                    Write-Output "Please upgrade manually"
                }
    
         }
    } 
}
#Upragade ldap schema no matter what is the upgrade version, but if the archive is already 6.5 we assume the schema is up to date
if ($upgradeLdap -and !($current_build.StartsWith(6.5))) {
    Write-Output "`r`nProcessing Ldap"
    Write-Output "----------------------"
    $clusterInfo['ldap'].Keys | ForEach-Object {
        if ($OKCreds -contains $_) {
                launchLinuxSchemaUpgrade -nodeType "ldap" -nodeIp $_
            } else {
                Write-Output "Credentials not working for this node"
                Write-Output "Please upgrade manually"
            }
         
    }
}

if ($upgradeArchive) {
    Write-Output "`r`nProcessing Archive nodes"
    Write-Output "------------------------------"

    $archiveUpgradeNeeded = $false
    $clusterInfo['archive'].Keys | foreach-object {
        if ($clusterInfo['archive'].$_.version -lt $upgrade_version) {
            $archiveUpgradeNeeded = $true
        }
    }

    if ($archiveUpgradeNeeded) {
        Write-Output "Archive Nodes Upgrade needed"
        if ( !(Test-Path -Path "$TEMPDIR\installer_$($upgrade_version)\$($packagesToInstall['netmail'].filename)") ) {
            # Download Archive Installer
            downloadMSI -url $packagesToInstall['netmail'].url `
                -filename $packagesToInstall['netmail'].filename `
                -destinationFolder $TEMPDIR\installer_$($upgrade_version)
        }
        $archiveNodesUpgraded = @{}
        $clusterInfo['archive'].Keys | foreach-object {
            if ($clusterInfo['archive'].$_.version -lt $upgrade_version) {
                if ($OKCreds -contains $_) {
                    # Copy Installer
                    Write-Host "Mounting Drive at $_"
                    New-PSDrive -name TEMP -PSProvider FileSystem -Root "\\$_\c$\$remoteTEMP" -Credential $windowsAdminCredentials
                    if ( ! (test-path -pathtype container "TEMP:\installer_$($upgrade_version)") ) {
                        New-Item -Path "TEMP:\" -Name "installer_$($upgrade_version)" -ItemType "directory"
                    }
                    Write-Host "`r`nCopying installer: $TEMPDIR\installer_$upgrade_version\$($packagesToInstall['netmail'].filename)"
                    Write-Host " to \\$_\c$\$remoteTEMP\installer_$upgrade_version"
                    Copy-Item "$TEMPDIR\installer_$upgrade_version\$($packagesToInstall['netmail'].filename)" `
                        -Destination "TEMP:\installer_$upgrade_version\$($packagesToInstall['netmail'].filename)" -Verbose
                    #Copy nodejs if 6.5 and if exists, as well as if upgrading to 6.5 and current version is not 6.5
                    if ($upgrade_version.StartsWith(6.5) -and !($clusterInfo['archive'].$_.version.StartsWith(6.5))){
                        Write-Host "We are going to update nodejs."
                        if (!(Test-Path $nodemsi -PathType leaf)){
                                Write-Host "Installation package is missing. Downlowad node-v14.11.0-x86.msi and install it manually on each updated node."
                        } else{
                           $batcommands = "@echo off `r`n"
                           $batcommands += "`r`nmsiexec.exe /i "+"$TEMPDIR\installer_$($upgrade_version)\node-v14.11.0-x86.msi"+" /QN /L*V "+'"'+"$TEMPDIR\installer_$($upgrade_version)\msilog.log"+'"'
                           New-item -Path . -Name "installnode.bat"-ItemType "file" -Value $batcommands -Force |Out-Null
                           Copy-Item $nodemsi -Destination "TEMP:\installer_$upgrade_version\" -Verbose
                           Copy-Item ".\installnode.bat" -Destination "TEMP:\installer_$upgrade_version\" -Verbose
                           #update nodejs
                           launchNodeJSUpgrade $_
                          }
                    }

                    Remove-PSDrive -Name TEMP
                    $archiveNodesUpgraded += (launchArchiveUpgrade -nodeIp $_)
                } else {
                    Write-Output "Credentials not working for this node"
                    Write-Output "Please upgrade manually"
                }
            } else {
                Write-Output "$_ version already at: $($clusterInfo['archive'].$_.version)"
            }
        }
        $jobs = @()
        $archiveNodesToRestart = @()
        $archiveNodesUpgraded.Keys | ForEach-Object { 
            if ($archiveNodesUpgraded[$_] -ne "Error" -and $archiveNodesUpgraded[$_] -ne "Skipped") {
                $jobs += $archiveNodesUpgraded[$_]
                $archiveNodesToRestart += $_
            }
        }
        Write-Output "Checking remote jobs status"
        checkJobStatus -jobs $jobs
        Write-Output "Restarting archive platform at remote nodes"
        restartArchive -archiveNodes $archiveNodesToRestart
    } else {
        Write-Output "Archive nodes upgrade not needed"
    }
}
#Updating Crawler
if ($upgradeCrawler) {
    Write-Output "`r`nProcessing Crawler nodes"
    Write-Output "------------------------------"

    $archiveUpgradeNeeded = $false
    $clusterInfo['crawler'].Keys | foreach-object {
        if ($clusterInfo['crawler'].$_.version -lt $upgrade_version) {
            $archiveUpgradeNeeded = $true
        }
    }

    if ($archiveUpgradeNeeded) {
        Write-Output "Crawler Nodes Upgrade needed"
        if ( !(Test-Path -Path "$TEMPDIR\installer_$($upgrade_version)\$($packagesToInstall['netmail'].filename)") ) {
            # Download Archive Installer
            downloadMSI -url $packagesToInstall['netmail'].url `
                -filename $packagesToInstall['netmail'].filename `
                -destinationFolder $TEMPDIR\installer_$($upgrade_version)
        }
        $archiveNodesUpgraded = @{}
        $clusterInfo['crawler'].Keys | foreach-object {
            if ($clusterInfo['crawler'].$_.version -lt $upgrade_version) {
                if ($OKCreds -contains $_) {
                    # Copy Installer
                    Write-Host "Mounting Drive at $_"
                    New-PSDrive -name TEMP -PSProvider FileSystem -Root "\\$_\c$\$remoteTEMP" -Credential $windowsAdminCredentials
                    if ( ! (test-path -pathtype container "TEMP:\installer_$($upgrade_version)") ) {
                        New-Item -Path "TEMP:\" -Name "installer_$($upgrade_version)" -ItemType "directory"
                    }
                    Write-Host "`r`nCopying installer: $TEMPDIR\installer_$upgrade_version\$($packagesToInstall['netmail'].filename)"
                    Write-Host " to \\$_\c$\$remoteTEMP\installer_$upgrade_version"
                    Copy-Item "$TEMPDIR\installer_$upgrade_version\$($packagesToInstall['netmail'].filename)" `
                        -Destination "TEMP:\installer_$upgrade_version\$($packagesToInstall['netmail'].filename)" -Verbose
                    #Copy nodejs if 6.5 and if exists, as well as if upgrading to 6.5 and current version is not 6.5
                    if ($upgrade_version.StartsWith(6.5) -and !($clusterInfo['crawler'].$_.version.StartsWith(6.5))){
                        if (!(Test-Path $nodemsi -PathType leaf)){
                                Write-Host "Installation package is missing. Downlowad node-v14.11.0-x86.msi and install it manually on each updated node."
                        } else{
                           $batcommands = "@echo off `r`n"
                           $batcommands += "`r`nmsiexec.exe /i "+"$TEMPDIR\installer_$($upgrade_version)\node-v14.11.0-x86.msi"+" /QN /L*V "+'"'+"$TEMPDIR\installer_$($upgrade_version)\msilog.log"+'"'
                           New-item -Path . -Name "installnode.bat"-ItemType "file" -Value $batcommands -Force |Out-Null
                           Copy-Item $nodemsi -Destination "TEMP:\installer_$upgrade_version\" -Verbose
                           Copy-Item ".\installnode.bat" -Destination "TEMP:\installer_$upgrade_version\" -Verbose
                           #update nodejs
                           launchNodeJSUpgrade $_

                          }
                    }

                    Remove-PSDrive -Name TEMP
                    $archiveNodesUpgraded += (launchArchiveUpgrade -nodeIp $_)
                } else {
                    Write-Output "Credentials not working for this node"
                    Write-Output "Please upgrade manually"
                }
            } else {
                Write-Output "$_ version already at: $($clusterInfo['crawler'].$_.version)"
            }
        }
        $jobs = @()
        $archiveNodesToRestart = @()
        $archiveNodesUpgraded.Keys | ForEach-Object { 
            if ($archiveNodesUpgraded[$_] -ne "Error" -and $archiveNodesUpgraded[$_] -ne "Skipped") {
                $jobs += $archiveNodesUpgraded[$_]
                $archiveNodesToRestart += $_
            }
        }
        Write-Output "Checking remote jobs status"
        checkJobStatus -jobs $jobs
        Write-Output "Restarting archive platform at remote nodes"
        restartArchive -archiveNodes $archiveNodesToRestart
    } else {
        Write-Output "Archive nodes upgrade not needed"
    }
}
#updating xml with api key on crawler reuse the same key in xgwxmlv, if update is from 6.4. Checking if archive version is 6.5. We assume if it is, then we don't need to upatethe file,
if ($upgradeCrawler -and !($current_build.StartsWith(6.5))) {
    $tenantsOrgDns | ForEach-Object {
        discoverCrawlerNodes -tenantOrgDn $_ -windowsAdminCredentials $windowsAdminCredentials -updateAPIKey
    }
}

# Create mplus_warning table if not exists and if the the version on the archive node is not 6.5. Not 6.5 means lower, like 6.4
if (!($current_build.StartsWith(6.5))){
    $tenantsOrgDns | ForEach-Object {
            updatepostgres -tenantDn $_ -postgresql_admin_password $postgresql_admin_password
        }
}


#Updating xgwxmlv cloud.crawler_list for each tenant and if archive node is not 6.5

if (!($current_build.StartsWith(6.5))) {
    $clusterInfo['dp'].Keys | ForEach-Object {
        update-providerconfig -remote_provider $_
        }
}
    
# Fixing tenant dn, if the archive nodes is not 6.5, we assume that the cluster is set with the new script or are updated already from 6.4, which fixes the problem
if (!($current_build.StartsWith(6.5))){
    $tenantsOrgDns | ForEach-Object {
            fixtenantdn -tenantDn $_
        }
}
Write-Output "`r`n---------------"
Write-Output "Script Finished`r`n"
Write-Output "Check all services are started. Start/Restart if needed."
Write-Output "You need to reconfigure Sync user tab. For on-prem add AD details, for o365 - tenant id and select Azure."
Write-Output "Check in LDAP tenantid\platform\users, if for whateve reason there is a cache created, delete it."
Write-Output "Run User sync job."
Write-Output "To be able to see old (6.4) archive, run C:\Program Files (x86)\Messaging Architects\netcore\Archive\Archive2Identity.exe"
