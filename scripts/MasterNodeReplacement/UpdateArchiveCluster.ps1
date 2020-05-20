<#

.SYNOPSIS
This script updates ClusterConfig.xml across the Archive Cluster.
It needs:
Windows credentials for all of the archive cluster's nodes
The old and new Master IP addresses to be replaced
A comma separated list with all the remaining archive nodes' IP addresses in the cluster

.EXAMPLE
.\UpdateArchiveCluster.ps1 -windowsAdminPassword 'myPass1029482!@#' -oldMaster "1.2.3.4" -newMaster "2.3.4.5" -nodesList "2.3.4.6,2.3.4.7,2.3.4.8,2.3.4.5"

#>
Param(
    [Parameter()]
    [String]$windowsAdminUser = "Administrator",
    [Parameter(Mandatory)]
    [String]$windowsAdminPassword,
    [Parameter(Mandatory)]
    [String]$oldMaster,
    [Parameter(Mandatory)]
    [String]$newMaster,
    [Parameter(Mandatory)]
    [String]$nodesList
)
$myName =  ($PSCommandPath -split '\\')[-1]
Write-Output "`r`nRunning $myName"

$nodesArray = $nodesList -split ','

if ($nodesArray -notcontains $newMaster) {
    $nodesArray += $newMaster
}

#Testing OS access to cluster
$windowsAdminPasswordSecureString = $windowsAdminPassword | ConvertTo-SecureString -AsPlainText -Force
$windowsAdminCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $windowsAdminUser, $windowsAdminPasswordSecureString
Set-Item wsman:\localhost\Client\TrustedHosts -value '*' -Confirm:$false -Force
$psSessions = @{ }
$nodesArray | ForEach-Object {
    if ($_ -ne $ipaddress) {
        Write-Output "`r`nTesting Windows credentials"
        $WindowsNodesCredsOK = @()
        $testSession = New-PSSession `
                            -Computer $_ `
                            -Credential $windowsAdminCredentials `
                            -ErrorAction SilentlyContinue
        if (-not($testSession)) {
            Write-Output "Cannot establish a powershell session to $_. please verify that the user ${windowsAdminUser} can log in as administrator"
            Write-Output "Skipping $_, it will need manual configuration"
        }
        else {
            Write-Output "User: ${windowsAdminUser} is able to connect to $_ successfully"
            $WindowsNodesCredsOK += $_
            $psSessions[$_] = $testSession
        }
    }
}
$stopPlatformScriptBlock = {
    if ( (get-service -DisplayName "NetGovern Platform Service").Status -notmatch "Stopped" ) {
        Write-Output "Stopping NetGovern Platform"
        Stop-Service -DisplayName "NetGovern Platform Service"
    } else {
        Write-Output "NetGovern Platform Service stopped already"
    }
}
$psSessions.Keys | ForEach-Object {
    Write-Output "Verifying NetGovern Platform Service status on $_"
    Invoke-Command -Session $psSessions[$_] -ScriptBlock $stopPlatformScriptBlock
}

$updateClusterConfigScriptBlock = {
    Write-Output "Load ClusterConfig.xml"
    [xml]$clusterConfig = Get-Content $env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml

    Write-Output "Backup up old to: ClusterConfig.xml_promotebkp"
    Rename-Item `
        -Path "$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml" `
        -NewName "ClusterConfig.xml_promotebkp"

    $nodeToDelete = $clusterConfig.GWOpenConfig.Nodes.Node | Where-Object {
        $_.NodeID -match $using:newMaster
    }
    if ($nodeToDelete) {
        Write-Output "Delete Worker node: $($nodeToDelete.NodeID)"
        $nodeToDelete.ParentNode.RemoveChild($nodeToDelete) | Out-Null
    }

    Write-Output "Update Master Node tag with new IP"
    $nodeToUpdate = $clusterConfig.GWOpenConfig.Nodes.Node | Where-Object {
        $_.Type -match "MasterAndWorker"
    }
    if ($nodeToUpdate) {
        $nodeToUpdate.NodeID = $using:newMaster
        $nodeToUpdate.URL = $nodeToUpdate.URL.Replace($using:oldMaster, $using:newMaster)
    }

    Write-Output "Update LDAP Connection String"
    $ldapConnString = $clusterConfig.GWOpenConfig.ThreadPoolDefinition.iConf.PRMS
    $ldapConnString.'#cdata-section' = $ldapConnString.'#cdata-section'.Replace($using:oldMaster, $using:newMaster)

    Write-Output "Saving ClusterConfig.xml"
    $clusterConfig.Save("$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml")
}

$psSessions.Keys | ForEach-Object {
    Write-Output "Updating ClusterConfig.xml on $_"
    Invoke-Command -Session $psSessions[$_] -ScriptBlock $updateClusterConfigScriptBlock
}

$updateClientAccessScriptBlock = {
    Write-Output "Updating Remote Provider properties with $using:newMaster"
    $jettySsl = Get-content -Path "$env:NETMAIL_BASE_DIR\..\RemoteProvider\jetty-ssl.xml"
    $jettySsl.Replace($using:oldMaster, $using:newMaster) | Out-File `
        -FilePath "$env:NETMAIL_BASE_DIR\..\RemoteProvider\jetty-ssl.xml" -Encoding ascii
    $xgwxmlv = Get-content -Path "$env:NETMAIL_BASE_DIR\..\RemoteProvider\xgwxmlv.cfg"
    $xgwxmlv.Replace($using:oldMaster, $using:newMaster) | Out-File `
        -FilePath "$env:NETMAIL_BASE_DIR\..\RemoteProvider\xgwxmlv.cfg" -Encoding ascii
}

$psSessions.Keys | ForEach-Object {
    Write-Output "Updating Client Access (xgwxmlv.cfg) on $_"
    Invoke-Command -Session $psSessions[$_] -ScriptBlock $updateClientAccessScriptBlock
}

Write-Output "Designating new Master in platform-info"
try {
    & cmd /C "C:\Program Files (x86)\Messaging Architects\Netmail WebAdmin\etc\scripts\setup\Win-DesignateMaster.bat"
} catch {
    Write-Output "Couldn't modify platform info json file"
}

Write-Output "Removing PS Sessions"
$psSessions.Keys | ForEach-Object {
    Write-Output "Removing PS Session $_"
    $psSessions[$_] | Remove-PSSession
}

Write-Output "Script $myName Finished`r`n"
