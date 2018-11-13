$cluster_info= @{ 'archive' = @{} ; 'index' = @{} ; 'dp' = @{} }
$ldapsearch = "$env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe" 
$curl_exe = "$env:NETMAIL_BASE_DIR\etc\scripts\setup\curl.exe"

Get-ChildItem -Path "$env:NETMAIL_BASE_DIR\etc\launcher.d\60*" | `
    ForEach-Object {
        # Parse ldap info
        $launcher_cmd = (Get-Content -Path $_.FullName | Select-String -Pattern "XAWAService") -split ' +(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)'
        $dp_dir = (Get-ItemProperty ($($launcher_cmd[3]).replace('"',''))).DirectoryName
        $xgwxmlv_cfg = Get-Content "$dp_dir\xgwxmlv.cfg"
        $edir_host = (($xgwxmlv_cfg | Select-String 'edir.host=').Line -split '=',2)[1]
        $edir_port = (($xgwxmlv_cfg | Select-String 'edir.port=').Line -split '=',2)[1]
        $edir_logindn = (($xgwxmlv_cfg | Select-String 'edir.logindn=').Line -split '=',2)[1]
        $edir_loginpwdclear = (($xgwxmlv_cfg | Select-String 'edir.loginpwdclear=').Line -split '=',2)[1]
        $edir_container = (($xgwxmlv_cfg | Select-String 'edir.container=').Line -split '=',2)[1]
        $base_dn = "cn=Nodes,cn=GWOpenNode," + $edir_container
        $tenant_id = [regex]::match($edir_container, ".o=(.*?),o=netmail").Groups[1].Value
        #ldap query
        $params = "-D `"${edir_logindn}`" -o ldif-wrap=200 -w ${edir_loginpwdclear} -p ${edir_port} -h ${edir_host} -b `"${base_dn}`" `"objectclass=maGWClusterNode`" cn maID"
        $ldif = Invoke-Expression "& `"$ldapsearch`" $params"
        #parse ldif results
        $a = $ldif | Select-String "Nodes, GWOpenNode, archiving," -Context 0, 3
        $a | ForEach-Object {
            $node_type = (($_.Context.PostContext | Select-String "cn:") -split 'cn: ')[1]
            if ($node_type -notmatch 'Search') {
                $archive = @{}
                $info_json = ''
                $server = @{}
                $server['tenant'] = $tenant_id          
                if ($node_type -match 'Master') { $node_type = "master"}
                if ($node_type -match 'Worker') { $node_type = "worker"}
                $server['type'] = $node_type
                $ip_address = (($_.Context.PostContext | Select-String "maID:") -split 'maID: ')[1].Trim()
                $params = '-k', '-s', "https://${ip_address}/info"
                $info_json = Invoke-Expression "& `"$curl_exe`" $params" 
                if (-not ([string]::IsNullOrEmpty($info_json))) {
                    $info_hash = @{}
                    $info_json = ($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }
                    $server['version'] = $info_hash['netmail-archive'].version
                    $server['name'] = $info_hash['netmail-platform'].name
                } else {
                    $server['version'] = "9.9.9.9"
                    $server['name'] = "not_reachable"
                }
                $archive[$ip_address] = $server
                if ($cluster_info['archive'].Count -eq 0) {
                    $cluster_info['archive'] = $archive
                } else {
                    $duplicated = $cluster_info['archive'].ContainsKey($ip_address)
                    if ($duplicated) {
                        $ip_address | Out-File -Append "duplicated_nodes.txt"
                        $archive[$ip_address] | Out-File -Append "duplicated_nodes.txt"
                    } else
                    {
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
$solr_properties = $solr_properties.Replace('hosts=','').Replace('/solr','')
$solr = ( $solr_properties -split ',' ) -Replace ':(.*)', ''
$solr | ForEach-Object {
    $info_json = ''
    $index = @{}
    $server = @{}
    $params = '-k', '-s', "https://$_/info"
    $info_json = Invoke-Expression "& `"$curl_exe`" $params" 
    if (-not ([string]::IsNullOrEmpty($info_json))) {
        $info_hash = @{}
        $info_json = ($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }
        $server['version'] = $info_hash['netmail-platform'].version
        $server['name'] = $info_hash['netmail-platform'].name
    } else {
        $server['version'] = "9.9.9.9"
        $server['name'] = "timeout"
    }
    $index[$_] = $server
    if ($cluster_info['index'].Count -eq 0) {
        $cluster_info['index'] = $index
    } else {
        $duplicated = $cluster_info['index'].ContainsKey($_)
        if ($duplicated) {
            $_ | Out-File -Append "$PSScriptRoot\duplicated_nodes.txt"
            $index[$_] | Out-File -Append "$PSScriptRoot\duplicated_nodes.txt"
        } else
        {
            $cluster_info['index'] += $index
        }
    }
}

# DP
$dp = @{}
$ip_address = "255.255.255.255"
$server = @{}
$params = '-k', '-s', "https://localhost/info"
$info_json = Invoke-Expression "& `"$curl_exe`" $params"
if (-not ([string]::IsNullOrEmpty($info_json))) {
    $info_hash = @{}
    $info_json = ($info_json -join "`n" | ConvertFrom-Json).psobject.properties | ForEach-Object { $info_hash[$_.Name] = $_.Value }
    $server['version'] = $info_hash['netmail-platform'].version
    $server['name'] = $info_hash['netmail-platform'].name
    $ip_address = $info_hash['netmail-platform'].ip
} else {
    $server['version'] = "9.9.9.9"
    $server['name'] = "timeout"
}
$dp[$ip_address] = $server
$cluster_info['dp'] = $dp

ConvertTo-Json $cluster_info -Depth 5 | Set-Content "$PSScriptRoot\my-cluster-info.json"
