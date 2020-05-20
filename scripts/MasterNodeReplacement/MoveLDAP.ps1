<#

.SYNOPSIS
This script creates a backup of a local postgresql DB and restores it to another server.
Admin Users & Passwords should match in both postgres systems

#>
Param(
    [Parameter()]
    [String]$windowsAdminUser= "Administrator",
    [Parameter(Mandatory)]
    [String]$windowsAdminPassword,
    [Parameter(Mandatory)]
    [String]$netmailPassword,
    [Parameter(Mandatory)]
    [String]$newMaster,
    [Parameter(Mandatory)]
    [String]$nodesList,
    [Parameter(Mandatory)]
    [String]$oldMaster,
    [Parameter(Mandatory)]
    [String]$workerReplica
)
$myName =  ($PSCommandPath -split '\\')[-1]
Write-Output "`r`nRunning $myName"
Set-Location $PSScriptRoot
#Source functions
. .\myfunctions.ps1

$nodesArray = $nodesList.Split(',')

#LDAP Connection info
$ldapAdminPassword = Get-Content "${env:NETMAIL_BASE_DIR}\var\dbf\eclients.dat"
$ldapAdminDn = "cn=eclients,cn=system,o=netmail" 

# Test ldap connectivity
Write-Output "Verify ldap connectivity to $oldMaster as $ldapAdminDn"
$ldapConn = TestLDAPConn -ldapServer $oldMaster -ldapAdminDn $ldapAdminDn -ldapAdminPassword $ldapAdminPassword
if ($ldapConn -eq 0) {
    Write-Output "Success`r`n"
} else {
    Throw "Cannot connect to ldap (port 389).  Cannot continue"
    Exit 1
}
$ldapConnection = createLdapConnection -ldapServer $oldMaster -ldapAdminDn $ldapAdminDn -ldapAdminPassword $ldapAdminPassword

addLdapDn -ldapConnection $ldapConnection `
    -dnToAdd "cn=Default Master($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,o=netmail" `
    -objectClass "maGWClusterNode"

modifyLdapDn -ldapConnection $ldapConnection `
    -dnToModify "cn=Default Master($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,o=netmail" `
    -attributeName "maId" -newValue $newMaster -modType "Add"

modifyLdapDn -ldapConnection $ldapConnection `
    -dnToModify "cn=Default Master($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,o=netmail" `
    -attributeName "description" -newValue "Master Node" -modType "Add"

deleteLdapDn -ldapConnection $ldapConnection `
    -dnToDelete "cn=Default Master($oldMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,o=netmail"

$masterOSName = (getNodeInfo -nodeIp $oldMaster)['netmail-platform'].name
if ($masterOSName) {
    deleteLdapDn -ldapConnection $ldapConnection `
        -dnToDelete "cn=$masterOSName,cn=system,o=netmail"
}

deleteLdapDn -ldapConnection $ldapConnection `
    -dnToDelete "cn=Worker node ($newMaster),cn=Nodes,cn=GWOpenNode,cn=archiving,o=netmail"

$windowsAdminPasswordSecureString = $windowsAdminPassword | ConvertTo-SecureString -AsPlainText -Force
$windowsAdminCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windowsAdminUser, $windowsAdminPasswordSecureString
Write-Output "Mapping oldMaster $oldMaster\c$\Program Files (x86)\Messaging Architects"
Try {
    New-PSDrive -name "oldMaster" -PSProvider FileSystem `
        -Root "\\$oldMaster\c$\Program Files (x86)\Messaging Architects" `
        -Credential $windowsAdminCredentials
}
catch {
    Throw "Cannot map \\$oldMaster\c$\Program Files (x86)\Messaging Architects as user: $windowsAdminUser"
    Exit 1
}
Write-Output "oldMaster: mapped successfully"
if ($newMaster -ne $workerReplica) {
    Write-Output "Configuring NetGovern Directory service"
    Copy-Item "$env:NETMAIL_BASE_DIR\etc\launcher.d-available\05-openldap.conf" -Destination "$env:NETMAIL_BASE_DIR\etc\launcher.d" -Force
    Restart-Service -DisplayName "NetGovern Platform Service"

    $retries = 0
    $directoryStatus = (Get-Service -DisplayName "NetGovern Directory" -ErrorAction SilentlyContinue).Status
    while ($directoryStatus -ne "Running" -and $retries -lt 10) {
        Write-Output "Waiting for NetGovern Directory to start"
        Start-Sleep 10
        $retries += 1
        $directoryStatus = (Get-Service -DisplayName "NetGovern Directory" -ErrorAction SilentlyContinue).Status
    }
    if ($retries -ge 10) {
        Write-Output "Timed Out waiting for NetGovern Directory (slapd) to start"
        Exit 1
    }

    Write-Output "Configuring LDAP"
    Write-Output "$env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureOpenLDAP.bat passnotneeded join`r`n"
    & $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureOpenLDAP.bat passnotneeded join


    Write-Output "Nodes certificates to get from $oldMaster"
    $nodesArray | Where-Object { $_ -ne $newMaster } | Write-Output
    $nodesArray | Where-Object { $_ -ne $newMaster } | ForEach-Object {
        Write-Output "Copying oldMaster:\Netmail WebAdmin\var\openldap\certs\$_.crt"
        Copy-Item -Path "oldMaster:\Netmail WebAdmin\var\openldap\certs\$_.crt" `
            -Destination "$env:NETMAIL_BASE_DIR\var\openldap\certs" -Force
    }

    Write-Output "Configuring MultiMaster replica"
    Write-Output "& $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureMMOpenLDAP.bat $newMaster $workerReplica`r`n"
    & $env:NETMAIL_BASE_DIR\etc\scripts\setup\ConfigureMMOpenLDAP.bat $newMaster $workerReplica
}


# Piggy tailing PS Drive to copy the license file
Copy-Item -Path "oldMaster:\netmail_license.xml" `
        -Destination "$env:NETMAIL_BASE_DIR\..\" -Force

Write-Output "Removing Old Master from cfs"
Write-Output "& $env:NETMAIL_BASE_DIR\sbin\cfs.exe cabandon $oldMaster"
& $env:NETMAIL_BASE_DIR\sbin\cfs.exe cabandon $oldMaster

#Testing OS access to cluster
Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force
$psSessions = @{}

$nodesArray + $oldMaster | ForEach-Object {
    if ($_ -ne $newMaster) {
        Write-Output "`r`nTesting Windows credentials"
        $WindowsNodesCredsOK = @()
        $testSession = New-PSSession `
                        -Computer $_ `
                        -Credential $windowsAdminCredentials `
                        -ErrorAction SilentlyContinue
        if (-not($testSession)) {
            Write-Output "Cannot establish a powershell session to $_. please verify that the user ${windowsAdminUser} can log in as administrator"
            Write-Output "Skipping $_, it will need manual configuration"
        } else {
            Write-Output "User: ${windowsAdminUser} is able to connect to $_ successfully"
            $WindowsNodesCredsOK += $_
            $psSessions[$_] = $testSession
        }
    }
}
if ($psSessions.Keys.Count -gt 0) {
    $psSessions.Keys | ForEach-Object {
        Write-Output "Stopping NetGovern Platform at $_"
        Invoke-Command -Session $psSessions[$_] -ScriptBlock { Stop-Service -DisplayName "NetGovern Platform Service" }
        if ($_ -eq $oldMaster) {
            Invoke-Command -Session $psSessions[$_] -ScriptBlock {
                Get-Service -DisplayName "NetGovern Platform Service" | Set-Service  -StartupType Disabled
            }
        }
    }

    Write-Output "Removing PS Sessions"
    $psSessions.Keys | ForEach-Object {
        Write-Output "Disconnecting from PS Session $_"
        $psSessions[$_] | Remove-PSSession
    }
}

Write-Output "Stopping NetGovern Platform locally"
Stop-Service -DisplayName "NetGovern Platform Service"

if ($newMaster -ne $workerReplica) {
    Write-Output "Configuring Worker replica multimaster"
    Write-Output "Mapping WorkerReplica $workerReplica\c$\Program Files (x86)\Messaging Architects"
    Try {
        New-PSDrive -name "WorkerReplica" -PSProvider FileSystem `
            -Root "\\$workerReplica\c$\Program Files (x86)\Messaging Architects" `
            -Credential $windowsAdminCredentials
    }
    catch {
        Write-Output "Cannot map \\$workerReplica\c$\Program Files (x86)\Messaging Architects as user: $windowsAdminUser"
    }
    Write-Output "WorkerReplica: mapped successfully"
    $multiMaster = Get-content -Path "WorkerReplica:\Netmail WebAdmin\etc\slapd-multimaster.conf"
    $multiMaster.Replace($oldMaster, $newMaster) | Out-File `
        -FilePath "WorkerReplica:\Netmail WebAdmin\etc\slapd-multimaster.conf" -Encoding ascii

    Write-Output "Update new ldap certs"
    $sslHash = (& $env:NETMAIL_BASE_DIR\sbin\openssl.exe x509 -noout -hash -in $env:NETMAIL_BASE_DIR\var\openldap\certs\$newMaster.crt).Trim()
    $Error.Clear()
    Remove-Item -Path "WorkerReplica:\Netmail WebAdmin\var\openldap\certs\$newMaster.crt"  -Force
    Copy-Item "$env:NETMAIL_BASE_DIR\var\openldap\certs\$newMaster.crt" -Destination "WorkerReplica:\Netmail WebAdmin\var\openldap\certs" -Force
    Copy-Item "$env:NETMAIL_BASE_DIR\var\openldap\certs\$newMaster.crt" -Destination "WorkerReplica:\Netmail WebAdmin\var\openldap\certs\$sslHash.0" -Force

    Write-Output "Remove old master node cert"
    Remove-Item -Path "WorkerReplica:\Netmail WebAdmin\var\openldap\certs\$oldMaster.crt"  -Force

    Remove-PSDrive -Name WorkerReplica

    Write-Output "Updating mdb.conf on workers"
    $psSessions.Keys | Where-Object { $_ -ne $oldMaster } | ForEach-Object {
        Write-Output "Mapping PSDrive Worker \\$_\c$\Program Files (x86)\Messaging Architects"
        Try {
            New-PSDrive -name "Worker" -PSProvider FileSystem `
                -Root "\\$_\c$\Program Files (x86)\Messaging Architects" `
                -Credential $windowsAdminCredentials
        }
        catch {
            Write-Output "Cannot map \\$_\c$\Program Files (x86)\Messaging Architects as user: $windowsAdminUser"
        }
        Write-Output "Worker: mapped successfully"
        Write-Output "Updating mdb.conf"
        $multiMaster = Get-content -Path "Worker:\Netmail WebAdmin\etc\mdb.conf"
        $multiMaster.Replace($oldMaster, $newMaster) | Out-File `
            -FilePath "Worker:\Netmail WebAdmin\etc\mdb.conf" -Encoding ascii
        Write-Output "Removing mapped PSDrive Worker"
        Remove-PSDrive -Name Worker
    }
} else {
    Write-Output "Removing MultiMaster configuration"
    Set-Content -Path "$env:NETMAIL_BASE_DIR\etc\slapd-multimaster.conf" -Value ""
    Set-Content -Path "$env:NETMAIL_BASE_DIR\etc\mdb.conf" -Value `
        (Get-Content -Path "$env:NETMAIL_BASE_DIR\etc\mdb.conf" | Select-String -Pattern $oldMaster -NotMatch)
}

Write-Output "Getting LDAP DB from oldMaster"
Copy-Item "oldMaster:\Netmail WebAdmin\var\openldap\data\DB_CONFIG" -Destination "$env:NETMAIL_BASE_DIR\var\openldap\data" -Force
Copy-Item "oldMaster:\Netmail WebAdmin\var\openldap\data\data.mdb" -Destination "$env:NETMAIL_BASE_DIR\var\openldap\data" -Force

Remove-PSDrive -Name oldMaster

Write-Output "Script $myName Finished`r`n"
