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
    $clusterInfo['archive'].Keys +@($clusterInfo['crawler'].Keys)| foreach-object { #added crawler
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
    if ((Test-NetConnection "http://artifactory.netmail.com/").PingSucceeded){
       Write-Host "Downloading ssh tools"
    }else{ Write-Host "Request the following tools:klink.exe and kscp.exe. `n`rYou must have them in the current directory, then type `"y`" or `"n`' to stop the script " 
        confirmInfo -unattended $unattended }

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

function TokenReplacement {
   Param(
       [Parameter(Mandatory=$True)]
        [string]$tokenized_content,
       [Parameter(Mandatory=$True)]
       [hashtable]$token_collection
    )
    $countter = (($tokens_coll.Keys).Count -1)
    
    For ($i = 0; $i -le $countter; $i++) {
    
    write-host "replace $($token_collection.Keys)[$i] with $token_collection.($($token_collection.Keys)[$i])"
    $tokenized_content = $tokenized_content.Replace($($token_collection.Keys)[$i],$token_collection.($($token_collection.Keys)[$i]))
    
    }
    return $tokenized_content
}

#Generate apid key 
function GenerateAPIDkey {
    Param(
       [Parameter(Mandatory=$True)]
        [string]$masternode,
        [Parameter(Mandatory=$True)]
        [string]$tenantid,
        [Parameter()]
        [string]$keyid
        )

$key = @{}
$param = @{"id"="$keyid"}
$uri = "https://$masternode"+":444/$tenantid/apikeys/"


$sblock = {
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$response = @{}
try{
$response = Invoke-WebRequest -Uri $Using:uri -Method Post -Body ($Using:param|ConvertTo-Json) -ContentType "application/json" 

}
catch {
    $_.Exception.Response.StatusCode.Value__
    $code = $_.Exception.Response.StatusCode.Value__
}

if($code -ne "409"){
    "IBtrue"    
    $key = ConvertFrom-Json $response
    $key
}else{ $response }
}

$urikey = $uri + $param.id
$sblock2 = {
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$response = @{}
try{
 Invoke-WebRequest -Uri $Using:urikey -ContentType "application/json" -Headers @{"accept"="application/json"} -Method Delete
 $response = Invoke-WebRequest -Uri $Using:uri -Method Post -Body ($Using:param|ConvertTo-Json) -ContentType "application/json" 
}
catch {
    $_.Exception.Response.StatusCode.Value__
    $code = $_.Exception.Response.StatusCode.Value__
}

$key = ConvertFrom-Json $response
$key
}

$respo = Invoke-Command -ScriptBlock $sblock -ComputerName $masternode

if ($respo -eq "409"){
    #"Delete existing Key and create new"
    $respo = Invoke-Command -ScriptBlock $sblock2 -ComputerName $masternode  
   }

#$respo.id
$keyvalue = $respo.apikey
return $keyvalue
}


function stopArchive {
    Param(
        [Parameter()]
        [string[]]$archiveNodes
    )
    foreach ($archiveNodeToBeStoped in $archiveNodes) {
        Write-Host "`r`nStopinging Launcher @ $archiveNodeToBeStoped"
        try {
            Invoke-Command -ScriptBlock { Stop-Service NetmailLauncherService } -ComputerName $archiveNodeToBeStoped -Credential $windowsAdminCredentials -ErrorAction Stop
        }
        catch {
            Write-Host "`r`nCannot start Launcher Service at $archiveNodeToBeStoped"
        }
    }
}

function startArchive {
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
            Copy-Item  "Master:\Netmail WebAdmin\var\dbf\eclients.dat" -Destination ".\eclients.dat_$tenantId"
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
        foreach ($worker IN $workerList){
                    Write-host "Worker $worker"
                    New-PSDrive -name "Worker" -PSProvider FileSystem `
                    -Root "\\$worker\c$\Program Files (x86)\Messaging Architects" `
                    -Credential $windowsAdminCredentials -ErrorAction Stop | Out-Null
                    Write-Host "Worker: mapped successfully"
                    #check if eclients exists
                    if (Test-Path -Path "Worker:\Netmail WebAdmin\var\dbf\eclients.dat" -PathType Leaf){
                        Write-host "Worker $worker has eclients.dat already"
                        } else {
                                Write-host "Worker $worker has no eclients.dat. Copying."
                                Copy-Item ".\eclients.dat_$tenantId" -Destination "Worker:\Netmail WebAdmin\var\dbf\eclients.dat"
                            }
                   Remove-PSDrive -Name "Worker" 
                }
        $workerList + @($master)| Select-Object -Unique | ForEach-Object {
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

function restartArchive {
    Param(
        [Parameter()]
        [string[]]$archiveNodes
    )
    foreach ($archiveNodeToBeStarted in $archiveNodes) {
        Start-Sleep -Seconds 10
        Write-Host "`r`nRestarting Launcher @ $archiveNodeToBeStarted"
        try {
            
            for($i = 0; $i -le 10; $i++){
                    Invoke-Command -ScriptBlock { Stop-Service NetmailLauncherService } -ComputerName $archiveNodeToBeStarted -Credential $windowsAdminCredentials -ErrorAction SilentlyContinue
                    if ((Invoke-Command -ScriptBlock { Get-Service NetmailLauncherService } -ComputerName $archiveNodeToBeStarted -Credential $windowsAdminCredentials).Status -eq "Stopped" ){ break }
                    Write-Host "Trying to stop services on $archiveNodeToBeStarted, iteration $i"
                    #(Invoke-Command -ScriptBlock { Get-Service NetmailLauncherService } -ComputerName $archiveNodeToBeStarted -Credential $windowsAdminCredentials).Status
                }
            Invoke-Command -ScriptBlock { Start-Service NetmailLauncherService } -ComputerName $archiveNodeToBeStarted -Credential $windowsAdminCredentials -ErrorAction Stop
        }
        catch {
            Write-Host "`r`nCannot start Launcher Service at $archiveNodeToBeStarted"
        }
    }
}

#Discover crawler. Needs to be tested with multiple crawler nodes. curnetly-one per tenant
function discoverCrawlerNodes {
    Param (
        [Parameter()]
        [string]$tenantOrgDn,
        [Parameter()]
        [System.Management.Automation.PSCredential]$windowsAdminCredentials,
        [Parameter()]
        [Switch]$updateAPIKey = $false
    )

    $crawler = $null
    $CrawlerList = @()
    Write-Host "`r`nDiscovering Crawler Nodes for tenant $tenantOrgDn"
    Write-Host "-------------------------"
    #ldap query to get Master Node
    $baseDn = "cn=Nodes,cn=GWOpenNode,cn=archiving,$tenantOrgDn"
    $tenantId = [regex]::match($tenantOrgDn, "o=(.*?),o=netmail").Groups[1].Value
    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200"
    $params += " -w ${ldap_admin_dn_password} -p ${ldapPort} -h ${ldapServer}"
    $params += " -b `"${baseDn}`" `"objectclass=maGWClusterNode`" cn maID"
    $ldif = Invoke-Expression "& `"$ldapsearch`" $params"
    #parse ldif results
     #IB: added Crawler nodes discovery and update apid key in xml
    $CrawlerFound = $false
    ($ldif | Select-String "Nodes, GWOpenNode, archiving," -Context 0, 3) | `
    ForEach-Object {
        $nodeType = (($_.Context.PostContext | Select-String "cn:") -split 'cn: ')[1]
        if ($nodeType -match 'Crawler') {
            $crawler = (($_.Context.PostContext | Select-String "maID:") -split 'maID: ')[1].Trim()
            $crawler = ($crawler -split ":")[0].Trim()
            $CrawlerList += ($crawler)
            Write-Host "Found Crawler: $crawler"
            $crawlerFound = $true
        }
        if ($nodeType -match 'Master') {
            $master = (($_.Context.PostContext | Select-String "maID:") -split 'maID: ')[1].Trim()
           
        }
    }

    if ($updateAPIKey -and !$crawlerFound){
        Write-Host "Tenat $tenantId has no crawler"
    }

    if ($updateAPIKey -and $crawlerFound){
        . .\basedata6.5
        #if services on master not running we cannot generated key
        if((Invoke-Command -ScriptBlock { (Get-Service NetmailLauncherService) } -ComputerName $master -Credential $windowsAdminCredentials).Status -ne "Running"){
            Write-host "NetmailLauncherService on $master is not running. Start the services and type yes to continue"
            confirmInfo -unattended $unattended
        }
        $unixdate = [int][double]::Parse((Get-Date -UFormat %s))
        Write-Host "Updating applicationContext.xml and servicesettings.json"
        Write-Host "TENANT ID IS $tenantId "
        Write-Host "Mounting Drive at $crawler"
        New-PSDrive -name TEMP -PSProvider FileSystem -Root "\\$crawler\c$\Program Files (x86)\Messaging Architects" -Credential $windowsAdminCredentials
        #Get-Item -Path TEMP:\applicationContext.xml 
        Copy-Item "TEMP:\Crawler\conf\applicationContext.xml" -Destination ".\applicationContext.xml" -Verbose
        Write-Host "`r`nBackup  applicationContext.xml"
        Copy-Item "TEMP:\Crawler\conf\applicationContext.xml" -Destination "TEMP:\Crawler\conf\applicationContext.xml.$unixdate" -Verbose
        Copy-Item "TEMP:\netcore\archive\servicesettings.json" -Destination "TEMP:\netcore\archive\servicesettings.json.$unixdate" -Verbose
        
        #stopArchive $crawler
    #Generate new key
        $keyvalue = $null
        $a = 1
        for ($i=0; $i -le 10; $i++){
            $keyvalue = GenerateAPIDkey -masternode $master -tenantid $tenantId -keyid "apidHostKey"
            Write-Output "Generating APIDKey, iteration $i"
            Write-Host " Key value is [$keyvalue]"
             if ($keyvalue -ne $null){break}
            }

        $applicationContext_xml= @()
        $tokenized_content = @()
        [xml]$applicationContext = Get-Content ".\applicationContext.xml"
                    #$indexclass = $applicationContext.beans.bean.class.IndexOf("com.primadesk.is.sys.crawler.CrawlerContextImpl")

        #create var (key:value) for replacement
        $tokens_coll = @{}
        $tokens_coll.MASTERNODEIP = $master
        $tokens_coll.KEYVALUE = ([String]$keyvalue).TrimStart(" ")
        $tokens_coll.LDAPID = $applicationContext.beans.bean[27].property[10].value
        $tokens_coll.ECLIENTDN = $applicationContext.beans.bean[27].property[13].value
        $tokens_coll.ECLIENTPASS = $applicationContext.beans.bean[27].property[14].value
        $tokens_coll.LDAPCONTAINER = $applicationContext.beans.bean[27].property[15].value

        #Write-Host " Key value is [$($tokens_coll.KEYVALUE)] double check" #for trouble shooting
        $keyfilePath = "$PSScriptRoot/$master_" + "Crawler_apikey.txt"
        Set-Content -Value $($tokens_coll.KEYVALUE) -Path $($keyfilePath)

        $applicationContext_xml = TokenReplacement -tokenized_content $applicationContext_base -token_collection $tokens_coll
        Write-Host "`r`nSet new content in applicationContext.xml"
        Set-Content -Value $applicationContext_xml -Path ".\applicationContext.xml_$tenantId"
        Copy-Item ".\applicationContext.xml_$tenantId" -Destination "TEMP:\Crawler\conf\applicationContext.xml"  -Verbose
        $apiurl = "https://"+$master+":444"
        $servicesettings = Get-Content -Raw -Path "TEMP:\netcore\archive\servicesettings.json" |ConvertFrom-Json
        $servicesettings.Netgovern.AdminAPI.Key = ([String]$keyvalue).TrimStart(" ")
        $servicesettings.Netgovern.AdminAPI.URLs = [Object[]]"$apiurl"
        Write-Output "Set content ot servicesettings.json"
        $servicesettings|ConvertTo-Json -Depth 50 |Set-Content -Path "TEMP:\netcore\archive\servicesettings.json" -Force
        Copy-Item -Path "TEMP:\netcore\archive\servicesettings.json" -Destination "./servicesettings.json_$tenantId"
        Remove-PSDrive -Name TEMP

        Write-Output "Stop platform at $crawler nodes"
        #restartArchive -archiveNodes $crawler
        stopArchive $crawler
        Start-sleep -s 15
        Write-Output "Start platform at $crawler nodes"
        startArchive $crawler
         
       
    }
    if(! $updateAPIKey){
        $archive = @{ }
        if (! $crawlerFound) {
            Write-Host "Crawler not found"
        } else {
        
        $CrawlerList | Select-Object -Unique | ForEach-Object {
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
    $index = @{} #IB moved it out for loop
    $solrNodes = $solrNodes | Select-Object -Unique
    $solrNodes | ForEach-Object {
        $infoJson = ''
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
    Write-Host "`r`Crawler node:"
    Write-Host "------------"
    ConvertTo-Json $($cluster).crawler
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
        "sudo yum install -y dos2unix ""&&"" sudo dos2unix /home/$linux_admin_user/*.sh ""&&"" bash /home/$linux_admin_user/$nodeIp-launcher.sh" #IB:added sudo and var for the home folder
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
#IB:Function used when we update from 6.4 to 6.5 to update schema only, RPMS are not updated. Index stays 6.4. Migration is needed to solr8
function launchLinuxSchemaUpgrade {
    Param(
        [Parameter()]
        [string]$nodeIp,
        [Parameter()]
        [ValidateSet('index','ldap')]
        [string]$nodeType
    )
    
    $launcherScript= ""
    #INDEX schema update
    if ($nodeType -eq "index") {
        $launcherScript = "sudo wget --no-check-certificate -O $($packagesToInstall['netmail-index'].filename) $($packagesToInstall['netmail-index'].url)"
        $launcherScript += "`r`nsudo ls |grep INDEX |xargs -I{} rpm2cpio {}|cpio -ivd ./opt/ma/netmail/solr/conf/schema.xml"
        $launcherScript += "`r`nsudo cp /opt/ma/netmail/solr/conf/schema.xml /home/netmail/schema.xml.bckp"
        $launcherScript += "`r`nsudo cp ./opt/ma/netmail/solr/conf/schema.xml /opt/ma/netmail/solr/conf/schema.xml"
        #solrconfig
        $launcherScript += "`r`nsudo ls |grep INDEX |xargs -I{} rpm2cpio {}|cpio -ivd /opt/ma/netmail/solr/conf/solrconfig.xml ./opt/ma/netmail/solr/conf/solrconfig.xml"
        $launcherScript += "`r`nsudo cp /opt/ma/netmail/solr/conf/solrconfig.xml /home/netmail/solrconfig.xml.bckp"
        $launcherScript += "`r`nsudo cp ./opt/ma/netmail/solr/conf/solrconfig.xml /opt/ma/netmail/solr/conf/solrconfig.xml"
        $launcherScript += "`r`nsudo chmod +x /home/netmail/zkChanges.sh"
        $launcherScript += "`r`nsudo /home/netmail/zkChanges.sh"
        $launcherScript += "`r`nsudo systemctl restart netmail"
        $launcherScript | Out-File -FilePath "$PSScriptRoot\$nodeIp-launchSchemaUpdate.sh" 
        

            $kscpParameters = "-auto-store-sshkey", "-pw", `
        "${linux_admin_password}", "-l", "${linux_admin_user}", "$nodeIp-launchSchemaUpdate.sh"+" zkChanges.sh", "${nodeIp}:/home/$linux_admin_user/"
        $copyRpmsCommand = "${kscpExe} ${kscpParameters}"
        Write-Host "`r`Copying Update scripts to $nodeIp"
            try {
                Invoke-Expression $copyRpmsCommand
            }
            catch {
                Write-Host "`r`nCannot copy Update scripts to $nodeIp. You can manually copy $nodeIp-launchSchemaUpdate.sh and execute it on the index nodes"
                Break
            }
       $klinkParameters = "-t", "-auto-store-sshkey", "-pw", `
        "${linux_admin_password}", "-l", "${linux_admin_user}", "${nodeIp}", `
        "sudo yum install -y dos2unix ""&&"" sudo dos2unix /home/$linux_admin_user/*.sh ""&&"" bash /home/$linux_admin_user/$nodeIp-launchSchemaUpdate.sh"
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
    }


    #LDAP schema update
    if ($nodeType -eq "ldap") {
        $launcherScript = "sudo cp /opt/ma/netmail/etc/netmail.schema.ldif /home/netmail/netmail.schema.ldif_old"
        $launcherScript += "`r`nsudo cp /home/netmail/netmail.schema.ldif  /opt/ma/netmail/etc/netmail.schema.ldif"
        $launcherScript += "`r`nsudo systemctl restart netmail"
        $launcherScript | Out-File -FilePath "$PSScriptRoot\$nodeIp-launchLDIFSchemaUpdate.sh"
        Copy-Item "$env:NETMAIL_BASE_DIR\etc\netmail.schema.ldif" -Destination "$PSScriptRoot/netmail.schema.ldif"
        
        
        $kscpParameters = "-auto-store-sshkey", "-pw", `
        "${linux_admin_password}", "-l", "${linux_admin_user}", "$PSScriptRoot/netmail.schema.ldif", "${nodeIp}:/home/$linux_admin_user/"
        $copyRpmsCommand = "${kscpExe} ${kscpParameters}"

        Write-Host "`r`Copying LDIF schema to $nodeIp"
            try {
                 Invoke-Expression $copyRpmsCommand
            }
            catch {
                Write-Host "`r`nCannot copy Update SCHEMA to $nodeIp. You can manually copy it on the LDAP nodes"
        Break
    }
    
        $kscpParameters = "-auto-store-sshkey", "-pw", `
             "${linux_admin_password}", "-l", "${linux_admin_user}", "$nodeIp-launchLDIFSchemaUpdate.sh", "${nodeIp}:/home/$linux_admin_user/"
        $copyRpmsCommand = "${kscpExe} ${kscpParameters}"
        Write-Host "`r`Copying Update scripts to $nodeIp"
        try {
            Invoke-Expression $copyRpmsCommand
         }
        catch {
            Write-Host "`r`nCannot copy Update scripts to $nodeIp. You can manually copy $nodeIp-launchLDIFSchemaUpdate.sh and execute it on the LDAP nodes"
            Break
        }
        $klinkParameters = "-t", "-auto-store-sshkey", "-pw", `
            "${linux_admin_password}", "-l", "${linux_admin_user}", "${nodeIp}", `
            "sudo yum install -y dos2unix ""&&"" sudo dos2unix /home/$linux_admin_user/*.sh ""&&"" bash /home/$linux_admin_user/$nodeIp-launchLDIFSchemaUpdate.sh"
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

#IB added function for nodejs update, only for CrawlerUpdate6.5 script
$installnodeJSScriptBlock = {
    # Launch Install
    $path2nodejs = "$using:TEMPDIR\installer_$($using:upgrade_version)\installnode.bat"
    $nodelog = "$using:TEMPDIR\installer_$($using:upgrade_version)\node-log.txt"
    $argsss = "cmd.exe /c " + "'"+$path2nodejs+"'"
    $InstallNetGovernWorkingDir = "$using:TEMPDIR\installer_$($using:upgrade_version)"
   try {
        Invoke-Expression -Command:$argsss
    }
    Catch {
        Write-Host "Cannot launch installnode.bat"
        Exit 1
    }

}

function launchNodeJSUpgrade {
    Param(
        [Parameter()]
        [string]$nodeIp
    )
       
    Write-Host "Starting upgrade nodejs at $nodeIp"
    (Invoke-Command -ComputerName $nodeIp -ErrorAction Stop -ScriptBlock $installnodeJSScriptBlock)
 
}

#Get postgres details, create a table mplus_warning if not exists

function updatepostgres {
    Param (
        [Parameter()]
        [string]$tenantDn,
        [Parameter()]
        [string]$postgresql_admin_password
    )
    Write-Host "`r`nDiscovering Postgres deatails. Create a table mplus_warning if not exists"
    Write-Host "-------------------------"

    $baseDn = "cn=System_Syncab,cn=Jobs,cn=GWOpenNode,cn=archiving,$tenantDn"
    $baseDn
    $tenantId = [regex]::match($tenantDn, "o=(.*?),o=netmail").Groups[1].Value
    $tenantId
    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200"
    $params += " -w ${ldap_admin_dn_password} -p ${ldapPort} -h ${ldapServer}"
    $params += " -b `"${baseDn}`" `"objectclass=maGWOJob`" cn maParameters"
    $ldif = Invoke-Expression "& `"$ldapsearch`" $params"
    #parse ldif results
     
    $prm= [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String( (($ldif | Select-String "maParameters::*" -Context 0, 3) -split 'maParameters:: ')[1]))
    $prm -match "Server=(?<content>.*);" | Out-Null
    $pgIP = $Matches['content'] 
    $pgIP = $pgIP.Substring(0, $pgIP.IndexOf(';'))
    $prm -match "Database=(?<content>.*);" | Out-Null
    $database = $Matches['content']
    $database = $database.Substring(0, $database.IndexOf(';'))
    $prm -match "Uid=(?<content>.*);" | Out-Null
    $pguser = $Matches['content']
    $pguser = $pguser.Substring(0, $pguser.IndexOf(';'))
    $postgresql_server = $pgIP
    
    $env:PGHOSTADDR = $pgIP
    $env:PGUSER = "postgres" #we use the default PG admin, change it if it is needed
    $env:PGPASSWORD = $postgresql_admin_password
    $env:PGPORT = "5432" #we use deafault port, cnage it if it is needed
    $postgres_client = ${env:ProgramFiles(x86)} + "\PostgreSQL\9.3\bin\psql.exe"
    
    Write-Host "`r`Verify postgres login to $env:PGHOSTADDR : $env:PGPORT as $env:PGUSER"
    $probe_cmd = $null
    $probe_query = "`"select extname from pg_extension;`""
    $probe_cmd = (& $postgres_client -t -c $probe_query | Out-String).Trim()

    if([string]::IsNullOrEmpty($probe_cmd)) {
        Write-host "Cannot login to postgres. Check credentials and the port" $logfile -toStdOut
    
    } else {
                    "OK"
                    Write-Host "`r`nCreating table warning if not exist"
                    
            $create_mplus_warning_table = "`"CREATE TABLE IF NOT EXISTS `"mplus_warning`" (id serial NOT NULL, jobid character varying(255) NOT NULL, `
         jobdatetime character varying(50) NOT NULL, logtimestamp character varying(50) NOT NULL, account character varying(255) NOT NULL, `
         errorsource character varying(255), errordescription character varying(8000), errorstacktrace character varying(8000), messageid character varying(255), `
         messagesubject character varying(255), messagecreationdate character varying(50), runtimeid character varying(50), CONSTRAINT mplus_warning_pkey PRIMARY KEY (id)); `
         ALTER TABLE `"mplus_warning`" OWNER TO $pguser; `
         CREATE INDEX mplus_warning_account_idx ON mplus_warning USING btree (account COLLATE pg_catalog.`"default`"); `
         CREATE INDEX mplus_warning_jobdatetime_idx ON mplus_warning USING btree (jobdatetime COLLATE pg_catalog.`"default`"); `
         CREATE INDEX mplus_warning_jobid_idx ON mplus_warning USING btree (jobid COLLATE pg_catalog.`"default`"); `
         CREATE INDEX mplus_warning_jobtimestamp_idx ON mplus_warning USING btree (logtimestamp COLLATE pg_catalog.`"default`");`"" 
 
          $(& $postgres_client -d $database -c $create_mplus_warning_table)  *>&1 > "./pgtablecreationinfo.txt"

          #the version culd vary check with dev , if not working
          $updateversion = "`"UPDATE netmail_db_version SET ver = `'6.4.0.0`' WHERE id = 1;`"" 
          $(& $postgres_client -d $database -c $updateversion)  *>&1 > "./pgtablecreationinfo.txt"
          }
}

function update-providerconfig {
 Param (
        [Parameter()]
        [string]$remote_provider
    )
    Write-Host "`r`nUpdating remote provider cinfiguration $remote_provider"
    Write-Host "-------------------------"
    
    $cloud_crawler_list =$null
    Write-Host "Tenants $tenantsOrgDns"
    Try {
          New-PSDrive -name "DP" -PSProvider FileSystem -Root "\\$remote_provider\c$\Program Files (x86)\Messaging Architects" -Credential $windowsAdminCredentials
        } catch {
                    Write-Hos "Cannot map \\$remote_provider\c$\Program Files (x86)\Messaging Architects as user: $windows_admin_user" 
        }  
        "`r`nDP: mapped successfully`r`n"   
    $tenantsOrgDns | ForEach-Object {
                                
                            
                                    $tenantId= $_ 
                                    $tenantId = [regex]::match($tenantId, "o=(.*?),o=netmail").Groups[1].Value
                                    Write-Host "`r`nUpdating tenant $tenantId `r`n"
                                    #ldap query to get Master Node
                                    $baseDn = "cn=Nodes,cn=GWOpenNode,cn=archiving,$_"
                                    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200"
                                    $params += " -w ${ldap_admin_dn_password} -p ${ldapPort} -h ${ldapServer}"
                                    $params += " -b `"${baseDn}`" `"objectclass=maGWClusterNode`" cn maID"
                                    $ldif = Invoke-Expression "& `"$ldapsearch`" $params"
                                    #parse ldif results
         
                                    ($ldif | Select-String "Nodes, GWOpenNode, archiving," -Context 0, 3) | `
                                                    ForEach-Object {
                                                                    $nodeType = (($_.Context.PostContext | Select-String "cn:") -split 'cn: ')[1]
                                                                    if ($nodeType -match 'Master') {
                                                                    $master = (($_.Context.PostContext | Select-String "maID:") -split 'maID: ')[1].Trim()
                                                                    Write-Host "`r`nMaster for Tenant $tenantId is $master`r`n"
                                                                    }
                                                    }
        
                                    "`r`nUpdatind tenant $tenantId remote provider configuration`r`n"
                                    Copy-Item -Path "DP:\RemoteProvider_$tenantId\xgwxmlv.cfg" -Destination "DP:\RemoteProvider_$tenantId\xgwxmlv.cfg_$(get-date -f yyyyMMddhhmmss)"
                                    $xgwxmlv = $null
                                    $xgwxmlv = Get-Content "DP:\RemoteProvider_$tenantId\xgwxmlv.cfg"
                                           
                                        if ($clusterInfo['archive'].$($master).tenant -eq $tenantId){
                                        Write-Host "Master $master matches $tenantId"
                                            if (!($xgwxmlv -match "apid.key=")){
                                                Write-Host "`r`nTenat $tenantId has no key, will generate one.`r`n "
                                                $keyvalue = GenerateAPIDkey -masternode $master -tenantid $tenantId -keyid "DPkey"
                                                $keyvalue = ([String]$keyvalue).TrimStart(" ")
                                                $keyfilePath = "$PSScriptRoot/" + "DP_apikey.txt_$tenantId"
                                                Set-Content -Value $($keyvalue) -Path $($keyfilePath)
                                                $APIdKey = @("##########","# APIdKey #","##########","apid.key=$($keyvalue)")
                                                $openIddisable = "`r`nopenId.disable=false"
                                                $xgwxmlv = $xgwxmlv + $APIdKey + $openIddisable
                                            } else{   Write-Host "`r`nxgwxmlv for tenant $tenantId, has a key.`r`n"
                                                  $openIddisable = "`r`nopenId.disable=true"
                                                  $xgwxmlv = $xgwxmlv + $openIddisable
                                                  }

                                                  $clusterInfo['crawler'].Keys | ForEach-Object{
                                                  Write-Host "`r`nUpdating cloud.crawler_list for tenant $tenantId adding $_`r`n"
                                                        if ($clusterInfo['crawler'].$($_).tenant -eq $tenantId){
                                                            "Adding Crawler $_ to xgwxmlv"
                                                            $cloud_crawler_list += "cloud.crawler_list=https://$_/crawler/unifyle"+","
                                                            $cloud_crawler_list = $cloud_crawler_list.TrimEnd(",")
                                                            $xgwxmlv = $xgwxmlv -replace "^cloud.crawler_list=.*", $cloud_crawler_list
                                                            } else { Write-Host "`r`nTenant $tenantId has no crawler`r`n"}
                                                 }
                                   
                                   Set-Content -Value $xgwxmlv -Path "DP:\RemoteProvider_$tenantId\xgwxmlv.cfg" -Force
                                   
                                   }
        #Remove-PSDrive -Name DP
        }
        
        
 Remove-PSDrive -Name DP   
}

function fixtenantdn{
    Param (
        [Parameter()]
        [string]$tenantDn
        )
 
    $baseDn = $tenantDn
    Write-Host "`r`n Fixing tenant dn for $baseDn "
    Write-Host "-------------------------"
    $tenantId = [regex]::match($tenantDn, "o=(.*?),o=netmail").Groups[1].Value
    $tenantId

    $ldif_content = @("dn: $baseDn", "changetype: modify", "delete: o", "o: netmail")
    $ldif_filepath_name = "$PSScriptRoot\$tenantId.ldif"
    Set-Content -Value $ldif_content -Path $ldif_filepath_name
    $ldapmodify = "$env:NETMAIL_BASE_DIR\openldap\ldapmodify.exe"

    $params = "-D `"${ldap_admin_dn}`" -o ldif-wrap=200 -w ${ldap_admin_dn_password} -p ${ldapPort} -h ${ldapServer} -f $PSScriptRoot\$tenantId.ldif"
    Invoke-Expression "& `"$ldapmodify`" $params"

}

