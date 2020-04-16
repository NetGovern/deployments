function testLdapConnectivity {
    # Testing LDAP Connectivity
    [System.Environment]::SetEnvironmentVariable("LDAPTLS_REQCERT", "never")
    $ldapWhoami = "$env:NETMAIL_BASE_DIR\openldap\ldapwhoami.exe"
    $ldapWhoamiParams = @(
        "-vvv", 
        "-h", 
        $ldapServer, 
        "-p",
        $ldapPort
        "-D", 
        $ldap_admin_dn, 
        "-x", 
        "-w", 
        $ldap_admin_dn_password
    )
    $p = Start-Process -FilePath $ldapWhoami -ArgumentList $ldapWhoamiParams -Wait -PassThru
    if ( $p.ExitCode -ne 0 ) {
        Write-Host "`r`nCannot connect to LDAP server, please verify credentials for $ldap_admin_dn at $($ldapServer):$($ldapPort)"
        Exit 1
    }
}

function testCredentials{
    $OKCreds = @()
    Write-Host "`r`nTesting linux credentials"
    $linuxNodes = $clusterInfo['index'].Keys
    $linuxNodes += $clusterInfo['ldap'].Keys
    $linuxNodes | foreach-object {
        if ( $_ -ne "not_reachable" ) {
            $klinkParameters = "-t", "-auto-store-sshkey", "-pw", `
                "${linux_admin_password}", "-l", "${linux_admin_user}", "${_}", "sudo -n -l sudo"
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $klinkExe
            $pinfo.RedirectStandardError = $true
            $pinfo.RedirectStandardOutput = $true
            $pinfo.UseShellExecute = $false
            $pinfo.Arguments = $klinkParameters
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null
            if ( ! $p.WaitForExit(15000) ) {
                Write-Host "$klinkExe did not exit after 15s.  Killing process"
                $p.kill()
            }
            $stdout = $p.StandardOutput.ReadToEnd()
            if ($p.ExitCode -eq 0) {
                if ($stdout -match "/bin/sudo") { 
                    Write-Host "User: ${linux_admin_user} is able to connect to $_ and has sudo rights"
                    $OKCreds += $_
                } else {
                    Write-Host "Linux credentials pre-requisites not met.  Exiting script."
                    Write-Host "Please verify that the user ${linux_admin_user} can login to $_ and has sudo rights"
                    Exit 1
                }
            } else {
                Write-Host "Cannot connect to $_ with user: ${linux_admin_user}"
                if (!($skip_wrong_creds)) {
                    Write-Host "Linux credentials pre-requisites not met.  Exiting script."
                    Exit 1
                }
            }
        }
    }
    Write-Host "`r`nTesting Windows credentials"
    $clusterInfo['archive'].Keys | foreach-object {
        if ( $_ -ne "not_reachable" ) {
            $testSession = New-PSSession -Computer $_ -Credential $windowsAdminCredentials -ErrorAction SilentlyContinue
            if (-not($testSession)) {
                Write-Host "Cannot establish a powershell session to $_. please verify that the user ${windows_admin_user} can log in as administrator"
                if (!($skip_wrong_creds)) {
                    Write-Host "Windows credentials pre-requisites not met.  Exiting script."
                    Exit 1
                }
            }
            else {
                Write-Host "User: ${windows_admin_user} is able to connect to $_ successfully"
                Remove-PSSession $testSession
                $OKCreds += $_
            }
        }
    }
    return $OKCreds
}
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

function parametersSanityCheck {
    # Parameters sanity check
    if ( !($linux_admin_password) ) {
        $secure_string_linux_admin_password = Read-Host -Prompt `
            "Enter the password for the linux user account with sudo rights on the nodes" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_string_linux_admin_password)
        $linux_admin_password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
    if ( !($ldap_admin_dn_password) ) {
        $secure_string_ldap_admin_dn_password = Read-Host -Prompt `
            "Enter the password for the DN ldap administration user" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_string_ldap_admin_dn_password)
        $ldap_admin_dn_password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
    if ( !$windows_admin_password ) {
        $secure_string_windows_admin_password = Read-Host -Prompt `
            "Enter the password for the common windows user account with administrative rights on the nodes" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_string_windows_admin_password)
        $windows_admin_password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }

    if (!$test_connectivity) {
        if ( !($upgrade_version) ) {
            $upgrade_version = Read-Host -Prompt "Enter the version to upgrade to"
        }
        if ( !($manifest_url) ) {
            $manifest_url = Read-Host -Prompt "Enter the url where the NSSM/PLUS manifest can be found"
        }
    }
}

function getWindowsCredentials {
    param (
        [Parameter()]
        [string]$windowsPassword,
        [Parameter()]
        [string]$windowsUserName
    )
    $windowsPasswordSecureString = $windowsPassword | ConvertTo-SecureString -AsPlainText -Force
    $windowsCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windowsUserName, $windowsPasswordSecureString
    return $windowsCredentials
}

function getTenantOrgDns {
    #ldap query to get sub orgs (tenants)
    $tenantsOrgDns = @()
    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200 -w ${ldap_admin_dn_password} -p ${ldapPort} -h ${ldapServer} -b `"o=netmail`" `"objectclass=organization`" dn"
    $ldifOrgs = Invoke-Expression "& `"$ldapsearch`" $params"
    $ldifOrgs | Select-String "dn:" | foreach-object { 
        if (($_ -split 'dn: ')[1] -match ",o=netmail") {
            $tenantsOrgDns += , ($_ -split 'dn: ')[1]
        }
    }
    return $tenantsOrgDns
}

function getManifest {
    Param(
        [Parameter()]
        [string]$nssmUrl = "https://updates.netmail.com/UUID"
    )
    $curlParamsGet = '-k', '-s', $nssmUrl
    $curlParamsHttpCode = '-k', '-s', '-w', '"%{http_code}"', '-o', '/dev/null', $nssmUrl
    $status = 0
    $retries = 3
    $retry = 0

    while ($status -eq 0 -and $retry -lt $retries) {
        try {
            $r = Invoke-Expression "& `"$curlExe`" $curlParamsHttpCode"
            $status = $r
        }
        catch {
            Write-Host "Cannot connect to $nssmUrl"
            $status = 0
        }
        if ($status -eq 200) {
            $jsonResponse = Invoke-Expression "& `"$curlExe`" $curlParamsGet"
        } else {
            $retry += 1
            Start-Sleep 30
        }
    }
    if ($retry -ge $retries) {
        Write-Host "Last status code: $status"
        Exit 1
    }
    else {
        return $jsonResponse
    }
} 


function convertFromRawJson {
    Param(
        [Parameter()]
        [string]$json
    )
    if (-not ([string]::IsNullOrEmpty($json))) {
        $hashTable = @{}
        ($json -join "`n" | ConvertFrom-Json).psobject.properties | `
            ForEach-Object { 
                $hashTable[$_.Name] = $_.Value 
            }
        Return $hashTable
    } else {
        Write-Host "Raw json string is empty"
        Return 1
    }
}

function downloadLinuxTools {
    $curlExe = "$env:NETMAIL_BASE_DIR\etc\scripts\setup\curl.exe"
    $params = '-k', '-s', '-O', "http://artifactory.netmail.com/artifactory/windows-prereqs/klink.exe"
    Invoke-Expression "& `"$curlExe`" $params" 
    $params = '-k', '-s', '-O', "http://artifactory.netmail.com/artifactory/windows-prereqs/kscp.exe"
    Invoke-Expression "& `"$curlExe`" $params" 
}
function parseVersion {
    Param(
        [Parameter()]
        [string]$version,
        [Parameter()]
        [switch]$rpmDebug,
        [Parameter()]
        [string]$manifestUrl,
        [Parameter()]
        [string]$packagesList = "netmail-index,netmail-platform,netmail"
    )

    $pkgsToInstall = @{ }
    if (!$packagesList) {
        $packagesList = "netmail-index,netmail-platform,netmail"
    }
    $downloadHost = $manifestUrl.substring(0, $manifestUrl.LastIndexOf('/'))

    $rawManifest = getManifest -nssmUrl $manifestUrl
    $rawPackages = ""
    for ($i = 0; $i -lt $rawManifest.Count; $i++) {
        if ($i -ne 1 -and $i -ne ($rawManifest.Count - 2)) {
            $rawPackages += $rawManifest[$i]
        }
    }
    $rawPackages | out-file "nssm-test-raw-packages.txt"
    $manifest = convertFromRawJson -json $rawPackages
    $packagesList.split(',') | ForEach-Object {
        Write-Host "Processing package: $_"
        $requiredPkg = $_
        $uuid = ""
        $manifest.Keys | ForEach-Object {
            $versionString = ""
            $availablePkg = $manifest[$_]
            $availablePkgUuid = $_
            if ($availablePkg.name -eq $requiredPkg) {
                if ($requiredPkg -eq "netmail-index" -or $requiredPkg -eq "netmail-platform") {
                    if ($rpmDebug) {
                        if ($availablePkg.version[-1] -eq "True") {
                            $versionString = $($availablePkg.version)[0..3] -join '.'
                        }
                    }
                    else {
                        if ($availablePkg.version[-1] -ne "True") {
                            $versionString = $($availablePkg.version)[0..3] -join '.'
                        }
                    }
                }
                elseif ($requiredPkg -eq "netmail") {
                    $versionString = $($availablePkg.version)[0..3] -join '.'
                }
                if ($versionString) {
                    if ($versionString -eq $version) {
                        $uuid = $availablePkgUuid
                        write-host "Found matching version $versionString"
                    }
                }
            }
        }
        if ($uuid) {
            Write-Host "Found package details at $downloadHost/$uuid"
            $rawPackageManifest = getManifest -nssmUrl "$downloadHost/$uuid"
            $packageManifest = convertFromRawJson -json "$rawPackageManifest"
            $pkgsToInstall[$requiredPkg] = @{
                "filename" = $packageManifest['file'].filename.Replace(" ", "");
                "url" = "$downloadHost/$($packageManifest['file'].uuid)"
            }
        }
    }
    return $pkgsToInstall
}

function discoverArchiveNodes {
    Param (
        [Parameter()]
        [string]$tenantOrgDn,
        [Parameter()]
        [System.Management.Automation.PSCredential]$windowsAdminCredentials
    )
    Write-Host "`r`nDiscovering Archive Nodes"
    Write-Host "-------------------------"
    #ldap query to get Master Node
    $baseDn = "cn=Nodes,cn=GWOpenNode,cn=archiving,$tenantOrgDn"
    $tenantId = [regex]::match($tenantOrgDn, "o=(.*?),o=netmail").Groups[1].Value
    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200"
    $params += " -w ${ldap_admin_dn_password} -p ${ldapPort} -h ${ldapServer}"
    $params += " -b `"${baseDn}`" `"objectclass=maGWClusterNode`" cn maID"
    $ldif = Invoke-Expression "& `"$ldapsearch`" $params"
    #parse ldif results
    $masterFound = $false
    ($ldif | Select-String "Nodes, GWOpenNode, archiving," -Context 0, 3) | `
    ForEach-Object {
        $nodeType = (($_.Context.PostContext | Select-String "cn:") -split 'cn: ')[1]
        if ($nodeType -match 'Master') {
            $master = (($_.Context.PostContext | Select-String "maID:") -split 'maID: ')[1].Trim()
            Write-Host "Found Master: $master"
            $masterFound = $true
        }
    }
    $archive = @{ }
    if (! $masterFound) {
        Write-Host "Master not found"
    } else {
        Write-Host "Mapping Master \\$master\c$\Program Files (x86)\Messaging Architects"
        Try {
            New-PSDrive -name "Master" -PSProvider FileSystem `
                -Root "\\$master\c$\Program Files (x86)\Messaging Architects" `
                -Credential $windowsAdminCredentials -ErrorAction Stop | Out-Null
            Write-Host "Master: mapped successfully"
        } catch {
            Write-Host "Cannot map master's c$"
        }
        Try {
            [xml]$clusterConfig = Get-Content Master:\Config\ClusterConfig.xml
            $workerList = ($clusterConfig.GWOpenConfig.Nodes.Node | Where-Object {
                    $_.Type -eq "Worker"
                }).NodeID
            if ($workerList.GetType().Name -eq "String") {
                $workerList = @($workerList)
            }
        } catch {
            Write-Host "Cannot get list of Workers"
            $workerList = @()
        }
        $workerList + @($master) | Select-Object -Unique | ForEach-Object {
            $infoJson = ''
            $server = @{ }
            $server['tenant'] = $tenantId
            Write-Host "Attempting to contact https://$_/info to gather platform information"
            $params = '-k', '-s', "https://$_/info"
            $infoJson = Invoke-Expression "& `"$curlExe`" $params" 
            if (-not ([string]::IsNullOrEmpty($infoJson))) {
                $clusterInfo = @{ }
                $infoJson = ($infoJson -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $clusterInfo[$_.Name] = $_.Value }
                $server['version'] = $clusterInfo['netmail-archive'].version
                $server['name'] = $clusterInfo['netmail-platform'].name
                Write-Host "Platform information OK"
            }
            else {
                $server['version'] = "9.9.9.9"
                $server['name'] = "not_reachable"
                Write-Host "Cannot contact platform"
            }
            $archive[$_] = $server
        }
    }
    return $archive
}

function discoverSolrNodes {
    #Parse Nipe Config
    $solr = @()
    $index = @{}
    $solrProperties = Get-Content "$env:NETMAIL_BASE_DIR\..\Nipe\Config\solr.properties"
    $solrProperties = $solrProperties.Replace('hosts=', '').Replace('/solr', '')
    $solr = ( $solrProperties -split ',' ) -Replace ':(.*)', ''
    #Discover more solr nodes via zookeeper
    Write-Host "`r`nDiscovering Index Nodes"
    Write-Host "-------------------------"
    $solrNodes = @()
    $solr | ForEach-Object {
        $params = '-k', '-s', "http://$($_):31000/solr/admin/collections?action=clusterstatus""&""wt=xml"
        $responseXml = [xml](Invoke-Expression "& `"$curlExe`" $params")
        ($responseXml.response.lst | Where-Object {$_.name -eq "cluster"}).arr.str | `
            ForEach-Object { $solrNodes += $_.split(':')[0] }
    }
    $solrNodes = $solrNodes | Select-Object -Unique
    $solrNodes | ForEach-Object {
        $infoJson = ''
        $index = @{}
        $server = @{}
        Write-Host "Found: $_"
        Write-Host "Attempting to contact https://$_/info to gather platform information"
        $params = '-k', '-s', "https://$_/info"
        $infoJson = Invoke-Expression "& `"$curlExe`" $params" 
        if (-not ([string]::IsNullOrEmpty($infoJson))) {
            $clusterInfo = @{}
            $infoJson = ($infoJson -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $clusterInfo[$_.Name] = $_.Value }
            $server['version'] = $clusterInfo['netmail-platform'].version
            $server['name'] = $clusterInfo['netmail-platform'].name
            Write-Host "Platform information OK"
        }
        else {
            $server['version'] = "9.9.9.9"
            $server['name'] = "not_reachable"
            Write-Host "Cannot contact platform"
        }
        $index[$_] = $server
    }
    return $index
}

function getLdapPlatformDetails {
    # Ldap
    Write-Host "`r`nChecking Ldap platform component"
    Write-Host "----------------------------------------------------"
    $ldap = @{ }
    $server = @{ }
    $params = '-k', '-s', "https://$ldapServer/info"
    Write-Host "Attempting to contact https://$ldapServer/info to gather platform information"
    $infoJson = Invoke-Expression "& `"$curlExe`" $params"
    if (-not ([string]::IsNullOrEmpty($infoJson))) {
        $clusterInfo = @{ }
        $infoJson = ($infoJson -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $clusterInfo[$_.Name] = $_.Value }
        $server['version'] = $clusterInfo['netmail-platform'].version
        $server['name'] = $clusterInfo['netmail-platform'].name
        Write-Host "Platform information OK"
    }
    else {
        $server['version'] = "9.9.9.9"
        $server['name'] = "not_reachable"
        Write-Host "Cannot contact platform"
    }
    $ldap[$ldapServer] = $server
    return $ldap
}

function getRpPlatformDetails {
    # DP
    Write-Host "`r`nChecking my platform component (Remote Provider)"
    Write-Host "----------------------------------------------------"
    $dp = @{}
    $server = @{}
    Write-Host "Parsing C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\var\docroot\info"
    $clusterInfo = @{}
    $infoJson = Get-Content "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\var\docroot\info\netmail-remote-provider"
    $infoJson = ($infoJson -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $clusterInfo[$_.Name] = $_.Value }
    $server['version'] = $clusterInfo['version']
    $server['name'] = $env:COMPUTERNAME
    $dp[$rpIpAddress] = $server
    return $dp
}

function parseNipeProperties {
    # Parse ldap info
    $edirProperties = Get-Content "$env:NETMAIL_BASE_DIR\..\Nipe\Config\edir.properties"
    $ldapServer = (($edirProperties | Select-String 'edir.host=').Line -split '=', 2)[1]
    $ldapPort = (($edirProperties | Select-String 'edir.port=').Line -split '=', 2)[1]
    return $ldapServer, $ldapPort
}
function downloadMSI {
    Param (
        [Parameter()]
        [string]$url,
        [Parameter()]
        [string]$filename,
        [Parameter()]
        [string]$destinationFolder
    )
    #$curlDownloadFilePath = "`"$TEMPDIR\installer_$($upgrade_version)\$filename`""
    $curlDownloadFilePath = "`"$destinationFolder\$filename`""
    $params = '-k', '-o', $curlDownloadFilePath , $url
    if ( ! (test-path -pathtype container "$TEMPDIR\installer_$($upgrade_version)") ) {
        New-Item -Path "$TEMPDIR\" -Name "installer_$($upgrade_version)" -ItemType "directory" | Out-Null
    }
    Write-Host "`r`nDownloading Upgrade package"
    Invoke-Expression "& `"$curlExe`" $params"
}

function displayInfo {
    param (
        [Parameter()]
        [object]$cluster
    )
    Write-Host "`r`n----------------------------------------------------"
    Write-Host "`r`nPlease verify the following list of discovered nodes"
    Write-Host "The nodes with a version number of 9.9.9.9 were found"
    Write-Host "in the Cluster Configuration but the IP address is unreachable."
    Write-Host "They will not be upgraded."
    Write-Host "`r`nIf they are supposed to be active, stop the script and"
    Write-Host "try again once the missing nodes are back."
    Write-Host "`r`nRemote Provider:"
    Write-Host "----------------"
    ConvertTo-Json $($cluster).dp
    Write-Host "`r`nArchive nodes:"
    Write-Host "--------------"
    ConvertTo-Json $($cluster).archive
    Write-Host "`r`nIndex nodes:"
    Write-Host "------------"
    ConvertTo-Json $($cluster).index
    Write-Host "`r`Ldap node:"
    Write-Host "------------"
    ConvertTo-Json $($cluster).ldap
}

function confirmInfo {
    param (
        [bool]$unattended
    )
    if (!($unattended)) {
        $confirmation = ""
        while (($confirmation -ne "y") -and ($confirmation -ne "n") -and ($confirmation -ne "yes") -and ($confirmation -ne "no")) {
            $confirmation = (Read-Host "Proceed?(y/yes/n/no)").ToLower()
        }
        if (($confirmation -ne "y") -and ($confirmation -ne "yes")) {
            write-host "`r`nExiting"
            Exit 1
        }
    }
}

$installMsiScriptBlock = {
    function UnzipNpw {
        Param(
            [Parameter(Mandatory = $True)]
            [string]$pathToNpw,
            [Parameter(Mandatory = $True)]
            [string]$targetDir
        )
        $7zExe = "$env:PROGRAMFILES\7-Zip\7z.exe"
        $7zArgs = @(
            "x", 
            "$pathToNpw", 
            "-o$targetDir", 
            "-r",
            "-y")
        $p = Start-Process -FilePath $7zExe -ArgumentList $7zArgs -Wait -PassThru
        if ( $p.ExitCode -ne 0 ) {
            Write-Output "`r`nCannot unzip $pathToNpw as $targetDir"
            Write-Output "CRITICAL_ERROR"
            Exit 1
        }
    }

    $progressPreference = 'silentlyContinue'
    # Checking  PSH Version
    if ( $PSVersionTable.PSVersion.Major -lt 4 ) {
        Write-Host "Powershell version not supported: $($PSVersionTable.PSVersion.Major)"
    }
    Write-Host "Unzipping $using:TEMPDIR\installer_$($using:upgrade_version)\$($using:packagesToInstall['netmail'].filename)"
    UnzipNpw -pathToNpw "$using:TEMPDIR\installer_$($using:upgrade_version)\$($using:packagesToInstall['netmail'].filename)" `
         -targetDir "$using:TEMPDIR\installer_$($using:upgrade_version)"

    # Launch Install.bat
    $path2Installbat = "$using:TEMPDIR\installer_$($using:upgrade_version)\install.bat"
    $version = ((Get-Content $path2Installbat | Select-String "Update.exe version") -split "Update.exe version=")[1].Trim()
    Write-Host "Upgrading to version: $version"
    $InstallNetGovernArgument = "/c " + $path2Installbat
    $InstallNetGovernWorkingDir = "$using:TEMPDIR\installer_$($using:upgrade_version)"
    try {
        Start-Process cmd -ArgumentList $InstallNetGovernArgument -WorkingDirectory $InstallNetGovernWorkingDir -ErrorAction Stop
    }
    Catch {
        Write-Host "Cannot launch install.bat"
        Exit 1
    }

    $logFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    $Timer = 0
    $TimerLimit = 600
    $TimerIncrement = 10
    while ((-Not $logFilesPath) -And ($Timer -lt $TimerLimit)) {
        Write-Host "Waiting for the upgrade process to start"
        Start-Sleep $TimerIncrement
        $Timer = $Timer + $TimerIncrement
        $logFilesPath = Test-Path "C:\Program Files (x86)\Messaging Architects\_$($version)\install.log"
    }
    If ($Timer -ge $TimerLimit) {
        Write-Host "NetGovern installation (install.bat) timed out to create Log Files folder ($TimerLimit seconds)"
        Exit 1
    }

    $bootstrapLogFile = "C:\Program Files (x86)\Messaging Architects\_$($version)\bootstap.log" # Not a typo
    $msiFinished = (Get-Content $bootstrapLogFile | Select-String "msiexec exit code : 0" -ErrorAction Ignore)
    $netSNMPFinished = (Get-Content $bootstrapLogFile | Select-String "sc returned : 0" -ErrorAction Ignore)

    $Timer = 0
    $TimerLimit = 1800
    $TimerIncrement = 10
    while (((-Not $msiFinished) -or (-Not $netSNMPFinished)) -And ($Timer -lt $TimerLimit)) {
        if ($Timer%30 -lt 10) {
            Write-Host "Waiting for Installation tasks to finish, please wait"
            Write-Host "*****************************************************"
        }
        Start-Sleep $TimerIncrement
        $Timer = $Timer + $TimerIncrement
        $msiFinished = (Get-Content $bootstrapLogFile | Select-String "msiexec exit code : 0" -ErrorAction Ignore)
        $netSNMPFinished = (Get-Content $bootstrapLogFile | Select-String "sc returned : 0" -ErrorAction Ignore)
    }
    If ($Timer -ge $TimerLimit) {
        Write-Host "NetGovern installation (install.bat) timed out ($TimerLimit seconds)"
        Exit 1
    }

    Write-Host "-----------------------------"
    Write-Host "NetGovern Installation Finished"
}

function checkJobStatus {
    Param(
        [Parameter()]
        [string[]]$jobs
    )
    #Checking jobs status
    $Timer = 0
    $TimerLimit = 3600
    $TimerIncrement = 10
    $jobsLeft = $jobs.Count
    Write-Host "`r`nWaiting for Jobs to finish"
    while (($jobsLeft -gt 0) -And ($Timer -lt $TimerLimit)) {
        $jobsLeft = $jobs.Count
        if ( ($Timer % 180) -eq 0 ) {
            Write-Host "`r`nPlease wait for the remote and background jobs to finish..."
            Get-Job -Name $jobs | Select-Object Name, State, Location
        }
        Start-Sleep $TimerIncrement
        $Timer = $Timer + $TimerIncrement
        ForEach ($jobName in $jobs) {
            $jobState = (get-job -Name $jobName).JobStateInfo.State
            if ($jobState -eq "Completed") {
                $jobsLeft -= 1 
            }
            get-job -Name $jobName | Receive-Job | Out-File -Append "$($jobName).txt"
        }
    }
    If ($Timer -ge $TimerLimit) {
        Write-Host "`r`nRemote upgrades timed out after $TimerLimit seconds)"
    }
    else {
        Write-Host "---------------------------------------"
        Write-Host "`r`nAll Remote and background jobs finished"
    }
}

function restartArchive {
    Param(
        [Parameter()]
        [string[]]$archiveNodes
    )
    foreach ($archiveNodeToBeStarted in $archiveNodes) {
        Write-Host "`r`nStarting Launcher @ $archiveNodeToBeStarted"
        try {
            Invoke-Command -ScriptBlock { Start-Service NetmailLauncherService } -ComputerName $archiveNodeToBeStarted -Credential $windowsAdminCredentials -ErrorAction Stop
        }
        catch {
            Write-Host "`r`nCannot start Launcher Service at $archiveNodeToBeStarted"
        }
    }
}

function launchLinuxUpgrade {
    Param(
        [Parameter()]
        [string]$nodeIp,
        [Parameter()]
        [ValidateSet('index','ldap')]
        [string]$nodeType
    )
    $launcherScript = "chmod +x /home/$linux_admin_user/upgradeRpms.sh `r`n"
    $launcherScript += "sudo /home/$linux_admin_user/upgradeRpms.sh"
    $launcherScript += " $($packagesToInstall['netmail-platform'].url)"
    $launcherScript += " $($packagesToInstall['netmail-platform'].filename)"
    if ($nodeType -eq "index") {
        $launcherScript += " $($packagesToInstall['netmail-index'].url)"
        $launcherScript += " $($packagesToInstall['netmail-index'].filename)"
    }
    $launcherScript += "`r`nsudo systemctl restart netmail"
    $launcherScript | Out-File -FilePath $PSScriptRoot\$nodeIp-launcher.sh
    $kscpParameters = "-auto-store-sshkey", "-pw", `
        "${linux_admin_password}", "-l", "${linux_admin_user}", "upgradeRpms.sh $nodeIp-launcher.sh", "${nodeIp}:/home/$linux_admin_user/"
    $copyRpmsCommand = "${kscpExe} ${kscpParameters}"
    Write-Host "`r`Copying Update scripts to $nodeIp"
    try {
        Invoke-Expression $copyRpmsCommand
    }
    catch {
        Write-Host "`r`nCannot copy Update scripts to $nodeIp"
        Break
    }
    $klinkParameters = "-t", "-auto-store-sshkey", "-pw", `
        "${linux_admin_password}", "-l", "${linux_admin_user}", "${nodeIp}", `
        "sudo yum install -y dos2unix ""&&"" dos2unix /home/netmail/*.sh ""&&"" bash /home/$linux_admin_user/$nodeIp-launcher.sh"
    $installRpmsCommand = "& `"${klinkExe}`" ${klinkParameters}"
    $installRpmsScriptBlock = [Scriptblock]::Create($installRpmsCommand)
    $outputFileName = "$nodeType-$($nodeIp)-$(Get-Date -f "MMddhhmmss").txt"

    Write-Host "`r`nStarting $nodeType upgrade to $upgrade_version"
    try {
        Invoke-Command -ScriptBlock $installRpmsScriptBlock -ErrorAction Stop | Out-File $outputFileName
    }
    catch {
        Write-Host "`r`nCannot start $nodeType upgrade at $nodeIp"
        Break
    }
    Write-Host "Upgrade finished @ $nodeIp"
}

function launchArchiveUpgrade {
    Param(
        [Parameter()]
        [string]$nodeIp
    )
    $archiveNodeUpgrade = @{}
    $jobName = "JobAt$($nodeIp)-$(Get-Date -f "MMddhhmmss")"
    Write-Host "Starting Archive upgrade job at $nodeIp"
    (Invoke-Command -ScriptBlock $installMsiScriptBlock -ComputerName $nodeIp -Credential $windowsAdminCredentials -AsJob -JobName $jobName) | Out-Null
    if ($?) { 
        $archiveNodeUpgrade[$nodeIp] = $jobName
    }
    else { 
        Write-Host "`r`nJob could not be launched at $nodeIp, please run upgrade manually" 
        $archiveNodeUpgrade[$nodeIp] = "Error"
    }
    return $archiveNodeUpgrade
}
