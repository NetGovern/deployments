<#

.SYNOPSIS
This script promotes a worker node to replace a Master node in a cluster.
It needs to run from the worker to be promoted.

.EXAMPLE
.\SingleTenantReplaceMaster.ps1 `
    -windowsAdminUser Administrator `
    -windowsAdminPassword 'The Password' `
    -netmailPassword 'AnotherPassword'

#>
Param(
    [Parameter()]
    [String]$windowsAdminUser= "Administrator",
    [Parameter(Mandatory)]
    [String]$windowsAdminPassword,
    [Parameter(Mandatory)]
    [String]$netmailPassword
)
$myName =  ($PSCommandPath -split '\\')[-1]
Write-Output "`r`nRunning $myName"

Set-Location $PSScriptRoot
#Source functions
. .\myfunctions.ps1

[xml]$clusterConfig = Get-Content $env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml
$oldMaster = ($clusterConfig.GWOpenConfig.Nodes.Node | Where-Object {
        $_.Type -eq "MasterAndWorker"
    }).NodeID
$nodesList = ($clusterConfig.GWOpenConfig.Nodes.Node | Where-Object {
        $_.Type -eq "Worker"
    }).NodeID

$newMaster = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 | Select-Object IPV4Address).IPV4Address

$crawlersList = $nodesList | Where-Object { (getNodeInfo -nodeIp $_)['netmail-crawler'].configured }
$workerReplica = $nodesList | Where-Object { (getNodeInfo -nodeIp $_).Keys -contains "netmail-openldap" }

$Error.clear()
.\MoveDB.ps1 `
    -windowsAdminUser $windowsAdminUser `
    -windowsAdminPassword $windowsAdminPassword `
    -newMaster $newMaster `
    -oldMaster $oldMaster `
    -crawlersList ($crawlersList -join ',')

if ($Error) {
    Exit 1
}

$Error.clear()
.\MoveLDAP.ps1 `
    -windowsAdminUser $windowsAdminUser `
    -windowsAdminPassword $windowsAdminPassword `
    -netmailPassword $netmailPassword `
    -newMaster $newMaster `
    -oldMaster $oldMaster `
    -workerReplica $workerReplica `
    -nodesList ($nodesList -join ',')

if ($Error) {
    Exit 1
}

$Error.clear()
.\UpdateArchiveCluster.ps1 `
    -windowsAdminUser $windowsAdminUser `
    -windowsAdminPassword $windowsAdminPassword `
    -oldMaster $oldMaster `
    -newMaster $newMaster `
    -nodesList ($nodesList -join ',')

if ($Error) {
    Exit 1
}

$Error.clear()
.\MoveRP.ps1 `
    -windowsAdminUser $windowsAdminUser `
    -windowsAdminPassword $windowsAdminPassword `
    -oldMaster $oldMaster `
    -newMaster $newMaster

if ($Error) {
    Exit 1
}
RestartPlatform -windowsAdminUser $windowsAdminUser `
    -windowsAdminPassword $windowsAdminPassword `
    -nodesList ($nodesList -join ',')
Write-Output "Script $myName Finished`r`n"