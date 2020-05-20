function Write-Log {
    param (
        [Parameter()]
        [string]$Message,
        [Parameter()]
        [string]$logFilePath,
        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Severity = "INFO", ## Default to a low severity.
        [Parameter()]
        [switch] $toStdOut
    )
    
    if ( [string]::IsNullOrEmpty($Message) ) {
        $Message = "No output"
    }

    if ( [string]::IsNullOrEmpty($logFilePath) ) {
        $logFilePath = ".\DefaultLog.txt"
    }

    if ($toStdOut) {
        Write-Output $Message
    }

    $line = (Get-Date).ToString() + " -- [ $Severity ] -- $Message"
    
    if ( !(Test-Path -Path $logFilePath -PathType Leaf) ) {
        Set-Content -Path $logFilePath -Value $line
    }
    else {
        Add-Content -Path $logFilePath -Value $line
    }
}

function createLdapConnection {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$ldapServer,
        [Parameter(Mandatory = $True)]
        [string]$ldapAdminDn,
        [Parameter(Mandatory = $True)]
        [string]$ldapAdminPassword
    )
    [System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.Protocols")
    [System.Reflection.Assembly]::LoadWithPartialName("System.Net")

    $ldapCreds = new-object System.Net.NetworkCredential($ldapAdminDn, $ldapAdminPassword)
    $ldapDirectory = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($ldapServer)
    $ldapConnection = New-Object System.DirectoryServices.Protocols.LdapConnection($ldapDirectory, $ldapCreds)

    $ldapConnection.SessionOptions.SecureSocketLayer = $false;
    $ldapConnection.SessionOptions.ProtocolVersion = 3
    $ldapConnection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Basic

    $ldapConnection.Bind()

    return $ldapConnection
}
function deleteLdapDn {
    Param (
        [Parameter(Mandatory = $True)]
        [System.Object]$ldapConnection,
        [Parameter(Mandatory = $True)]
        [string]$dnToDelete
    )

    $deleteRequest = (new-object "System.DirectoryServices.Protocols.DeleteRequest")
    $deleteRequest.DistinguishedName = $dnToDelete;
    $ldapConnection[2].SendRequest($deleteRequest);
}
function addLdapDn {
    Param (
        [Parameter(Mandatory = $True)]
        [System.Object]$ldapConnection,
        [Parameter(Mandatory = $True)]
        [string]$dnToAdd,
        [Parameter(Mandatory = $True)]
        [string]$objectClass
    )

    $addRequest = (new-object "System.DirectoryServices.Protocols.AddRequest")
    $addRequest.DistinguishedName = $dnToAdd
    $attribute = New-Object "System.DirectoryServices.Protocols.DirectoryAttributeModification"
    $attribute.Name = "objectClass"
    $attribute.Add($objectClass)
    $addRequest.Attributes.Add($attribute)
    $ldapConnection[2].SendRequest($addRequest)

}

function addLdapAttribute {
    Param (
        [Parameter(Mandatory = $True)]
        [System.Object]$ldapConnection,
        [Parameter(Mandatory = $True)]
        [string]$baseDn,
        [Parameter(Mandatory = $True)]
        [string]$newAttribute,
        [Parameter(Mandatory = $True)]
        [string]$newValue
    )
    $deleteRequest = (new-object "System.DirectoryServices.Protocols.DeleteRequest")
    $deleteRequest.DistinguishedName = $dnToDelete;
    $ldapConnection[2].SendRequest($deleteRequest);
}

function modifyLdapDn {
    Param (
        [Parameter(Mandatory = $True)]
        [System.Object]$ldapConnection,
        [Parameter(Mandatory = $True)]
        [string]$dnToModify,
        [Parameter(Mandatory = $True)]
        [string]$attributeName,
        [Parameter(Mandatory = $True)]
        [string]$newValue,
        [Parameter(Mandatory = $True)]
        [ValidateSet('Add', 'Replace', 'Delete')]
        [string]$modType
    )
    $modifyRequest = (new-object "System.DirectoryServices.Protocols.ModifyRequest")
    $modifyRequest.DistinguishedName = $dnToModify
    $attribute = New-Object "System.DirectoryServices.Protocols.DirectoryAttributeModification"
    $attribute.Name = $attributeName
    $attribute.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::$modType
    $attribute.Add($newValue)

    $modifyRequest.Modifications.Add($attribute)
    $ldapConnection[2].SendRequest($modifyRequest);
}

function DecodeBase64 {
    Param(
        [Parameter()]
        [string]$value
	
    )
    if ($value) {
        return [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($value))
    }
    else { 
        return "" 
    } 
}

function TestLDAPConn {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$ldapServer,
        [Parameter(Mandatory = $True)]
        [string]$ldapAdminDn,
        [Parameter(Mandatory = $True)]
        [string]$ldapAdminPassword,
        [Parameter()]
        [switch]$ssl
    )

    [System.Environment]::SetEnvironmentVariable("LDAPTLS_REQCERT", "never")
    $ldapWhoami = "$env:NETMAIL_BASE_DIR\openldap\ldapwhoami.exe"
    if ($ssl) {
        $ldapUri = "ldaps://$ldapServer"
    }
    else {
        $ldapUri = "ldap://$ldapServer"
    }
    
    $testLdapConn = @(
        "-vvv", 
        "-H", 
        $ldapUri, 
        "-D", 
        $ldapAdminDn, 
        "-x", 
        "-w", 
        $ldapAdminPassword
    )

    $p = Start-Process -FilePath $ldapWhoami -ArgumentList $testLdapConn -Wait -NoNewWindow -PassThru
    return $p.ExitCode
}
function getClusterMembers {
    $cfs = "$env:NETMAIL_BASE_DIR\sbin\cfs.exe"
    $clusterMembersTmp = @()
    $clusterMembers = @()
    $params = 'status'
    $cfsStatus = Invoke-Expression "& `"$cfs`" $params"

    if (-not ([string]::IsNullOrEmpty($cfsStatus))) {
        $clusterMembersTmp += ($cfsStatus | Select-String 'ip')
        $clusterMembersTmp | ForEach-Object { 
            $clusterMembers += (($_ -split '":"', 2)[1] -split ':40', 2)[0]
        }
    }
    return $clusterMembers
} 

function GetNodeInfo {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$nodeIp
    )
    $curlExe = "$env:NETMAIL_BASE_DIR\etc\scripts\setup\curl.exe"
    $nodeInfo = @{ }
    $params = '-k', '-s', "https://${nodeIp}/info"
    $nodeInfoJson = Invoke-Expression "& `"$curlExe`" $params"
    if (-not ([string]::IsNullOrEmpty($nodeInfoJson))) {
        ($nodeInfoJson -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $nodeInfo[$_.Name] = $_.Value }
    }
    return $nodeInfo
}

function RestartPlatform {
    param (
        [Parameter(Mandatory = $True)]
        [string]$nodesList,
        [Parameter()]
        [String]$windowsAdminUser = "Administrator",
        [Parameter(Mandatory)]
        [String]$windowsAdminPassword
    )

    $nodesArray = $nodesList.Split(',')
    $windowsAdminPasswordSecureString = $windowsAdminPassword | ConvertTo-SecureString -AsPlainText -Force
    $windowsAdminCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windowsAdminUser, $windowsAdminPasswordSecureString
    $psSessions = @{ }
    Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force
    $nodesArray | ForEach-Object {
        Write-Output "`r`nTesting Windows credentials"
        $WindowsNodesCredsOK = @()
        $testSession = New-PSSession `
                            -Computer $_ `
                            -Credential $windowsAdminCredentials `
                            -ErrorAction SilentlyContinue
        if (-not($testSession)) {
            Write-Output "Cannot establish a powershell session to $_. please verify that the user ${windowsAdminUser} can log in as administrator"
            Write-Output "Skipping $_, it will a manual restart"
        }
        else {
            Write-Output "User: ${windowsAdminUser} is able to connect to $_ successfully"
            $WindowsNodesCredsOK += $_
            $psSessions[$_] = $testSession
        }
    }
    Write-Output "Restarting NetGovern Platform"
    $psSessions.Keys | ForEach-Object {
        Write-Output "Stopping $_"
        Invoke-Command -Session $psSessions[$_] -ScriptBlock {
            Write-Output "Current Status $($(Get-Service -DisplayName 'NetGovern Platform Service').Status)"
            if ((Get-Service -DisplayName "NetGovern Platform Service").Status -ne "Stopped") {
                Stop-Service -DisplayName "NetGovern Platform Service"
            }
            Write-Output "Starting $_"
            Start-Service -DisplayName "NetGovern Platform Service"
        }
    }

    Write-Output "Removing PS Sessions"
    $psSessions.Keys | ForEach-Object {
        Write-Output "Disconnecting from PS Session $_"
        $psSessions[$_] | Remove-PSSession
    }
}