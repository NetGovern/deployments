Param(
    [Parameter()]
    [string]$worker_to_retire_ip_address
)
. .\ngfunctions.ps1

#Backup Clusterconfig.xml
Copy-Item -Path "$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml" -Destination "$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig_$(get-date -f yyyyMMdd_HHmmss).xml"

[xml]$cluster_config = Get-Content "$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml"
$worker_to_retire = ($cluster_config.SelectNodes("//GWOpenConfig/Nodes/Node") | `
    Where-Object {$_.NodeID -eq $worker_to_retire_ip_address})
Write-Output "Worker Node to retire"
Write-Output $worker_to_retire
#Delete XML Node
($cluster_config.GWOpenConfig.Nodes).RemoveChild($worker_to_retire) | out-null
Output-Nice-Xml $cluster_config | Out-File -FilePath "$env:NETMAIL_BASE_DIR\..\Config\ClusterConfig.xml"