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
    [String]$newMaster,
    [Parameter(Mandatory)]
    [String]$oldMaster,
    [Parameter()]
    [String]$ldapServer,
    [Parameter()]
    [String]$crawlersList
)

$myName =  ($PSCommandPath -split '\\')[-1]
Write-Output "`r`nRunning $myName"

Set-Location $PSScriptRoot

#Source functions
. .\myfunctions.ps1

if ($crawlersList) {
    $crawlersArray = $crawlersList -split ','
}
# Setting up vars
$psql = "${env:ProgramFiles(x86)}\PostgreSQL\9.3\bin\psql.exe"
$pgDump = "${env:ProgramFiles(x86)}\PostgreSQL\9.3\bin\pg_dump.exe"
$ldapsearch = "$env:NETMAIL_BASE_DIR\openldap\ldapsearch.exe"

if (!$ldapServer) {
    $ldapServer = $oldMaster
}

# Parsing LDAP Connection info
$ldapAdminPassword = Get-Content "${env:NETMAIL_BASE_DIR}\var\dbf\eclients.dat"
$ldapAdminDn = "cn=eclients,cn=system,o=netmail" 

# Test ldap connectivity
Write-Output "Verify ldap connectivity to $ldapServer as $ldapAdminDn"
$ldapConn = TestLDAPConn -ldapServer $ldapServer -ldapAdminDn $ldapAdminDn -ldapAdminPassword $ldapAdminPassword
if ($ldapConn -eq 0) {
    $ldapUri = "ldap://$ldapServer"
    Write-Output "Success`r`n"
} else {
    $ldapConn = TestLDAPConn -ldapServer $ldapServer -ldapAdminDn $ldapAdminDn -ldapAdminPassword $ldapAdminPassword -ssl
    if ($ldapConn -eq 0) {
        $ldapUri = "ldaps://$ldapServer"
        Write-Output "Success`r`n"
    } else {
        Write-Output "Cannot connect to ldap nor ldaps.  Cannot continue"
        Exit 1
    }
}

Write-Output "Get Postgres connection string from LDAP"
$baseDn = "cn=archiving,o=netmail"
$params = "-D `"$ldapAdminDn`" -o ldif-wrap=no -w $ldapAdminPassword -H $ldapUri -b `"${baseDn}`" `"objectclass=maGWOpenNode`" maLogCnnString"

$ldif = Invoke-Expression "& `"$ldapsearch`" $params"
$pgConn = ((($ldif | Select-String "maLogCnnString: ") `
            -split 'String: ')[1]) -split ';'
$env:PGPASSWORD = ((($pgConn | Where-Object {$_ -match 'Pwd'}) -split '=')[1]).Trim()
$PGUserName = ((($pgConn | Where-Object { $_ -match 'Uid' }) -split '=')[1]).Trim()
$DBName = ((($pgConn | Where-Object { $_ -match 'Database' }) -split '=')[1]).Trim()


# Test Postgres login
Write-Output "Verify postgres login to $oldMaster as $PGUserName"
$probeQuery = "`"select extname from pg_extension;`""
$probeCmd = (& $psql -h $oldMaster -U $PGUserName -t -c $probeQuery | Out-String).Trim()
if ([string]::IsNullOrEmpty($probeCmd)) {
    Throw "Cannot login to postgres as postgresql_admin_user.  Cannot continue."
    Exit 1
} else {
    Write-Output "Success`r`n"
}

Write-Output "Backing Up DB"
$dumpLocation = "$env:TEMP\$DBName.dump"
try {
    & $pgDump -h $oldMaster -d $DBName -U $PGUserName -f $dumpLocation
} catch {
    Throw "Cannot take backup"
    Exit 1
}

Write-Output "Restoring DB"
try {
    & $psql -h $newMaster -U $PGUserName -c "CREATE DATABASE $DBName"
    & $psql -h $newMaster -U $PGUserName -d $DBName -f $dumpLocation
} catch {
    Throw "Cannot restore DB at $newMaster"
    Exit 1
}

Write-Output "Replacing DB values in ldap"
$PGCnnString = "Driver={PostgreSQL Unicode};Server=$newMaster;Port=5432;Database=$DBName;Uid=$PGUserName;Pwd=$env:PGPASSWORD;"

$ldapConnection = createLdapConnection -ldapServer $ldapServer -ldapAdminDn $ldapAdminDn -ldapAdminPassword $ldapAdminPassword

Write-Output "Replacing: cn=maReportCnnString,cn=GWOpenNode,cn=archiving,o=netmail"
Write-Output "New Value: $PGCnnString"
modifyLdapDn -ldapConnection $ldapConnection `
    -dnToModify "cn=GWOpenNode,cn=archiving,o=netmail" -attributeName "maReportCnnString" `
    -newValue $PGCnnString -modType "Replace"

Write-Output "Replacing: cn=maLogCnnString,cn=GWOpenNode,cn=archiving,o=netmail"
Write-Output "New Value: $PGCnnString"
modifyLdapDn -ldapConnection $ldapConnection `
    -dnToModify "cn=GWOpenNode,cn=archiving,o=netmail" -attributeName "maLogCnnString" `
    -newValue $PGCnnString -modType "Replace"

#ldap query for Jobs
$base_dn = "cn=Jobs,cn=GWOpenNode,cn=archiving,o=netmail"
$params = "-D `"$ldapAdminDn`" -o ldif-wrap=no -w $ldapAdminPassword -h $ldapServer -b `"${base_dn}`" `"objectclass=maGWOJob`" cn maParameters"
$ldif = Invoke-Expression "& `"$ldapsearch`" $params"
$jobs = @{}
$ldif | Select-String "Jobs, GWOpenNode, archiving," -Context 0, 3 | `
ForEach-Object {
    $jobPath = (($_.Context.PostContext | Select-String "dn:") -split 'dn: ')[1]
    $jobParam = DecodeBase64 -value ((($_.Context.PostContext | Select-String "maParameters::") -split 'maParameters::')[1])
    $jobs[$jobPath] = $jobParam
}
$jobs.Keys | ForEach-Object {
    if ($jobs[$_] -match "Server=$oldMaster") {
        Write-Host "Modifying $_"
        Write-Host "Changing Server=$oldMaster with Server=$newMaster"
        modifyLdapDn -ldapConnection $ldapConnection `
            -dnToModify $_ -attributeName "maParameters" `
            -newValue $jobs[$_].replace("Server=$oldMaster", "Server=$newMaster") `
            -modType "Replace"
    }
} 

if ($crawlersArray) {
    Write-Output "Configuring Crawler setting for the new DB location"
    Write-Output "Found the following crawler nodes"
    Write-Output $crawlersArray
    $crawlerNodePassword = ConvertTo-SecureString $windowsAdminPassword -AsPlainText -Force
    $crawlerNodeCreds = new-object -typename System.Management.Automation.PSCredential `
        -argumentlist $windowsAdminUser, $crawlerNodePassword
    $crawlersArray | ForEach-Object {
        #Map the drive
        Write-Output "Mapping Crawler: to  \\$_\c$\Program Files (x86)\Messaging Architects\Crawler"
        Try {
            New-PSDrive -name "Crawler" -PSProvider FileSystem `
                -Root "\\$_\c$\Program Files (x86)\Messaging Architects\Crawler" `
                -Credential $crawlerNodeCreds | Out-Null
        }
        catch {
            Throw "Cannot map \\$_\c$\Program Files (x86)\Messaging Architects as user: $windowsAdminUser"
            Exit 1
        }
        Write-Output "Crawler: mapped successfully"
        Write-Output "Modifying settings in apache-tomcat-7.0.40\webapps\unifyle\WEB-INF\classes\instanceContext.xml"
        $instanceContext = Get-content -Path ("Crawler:\apache-tomcat-7.0.40\webapps\unifyle\WEB-INF\classes\instanceContext.xml")
        $instanceContext = $instanceContext -replace '<property name="url.+', `
            "<property name=`"url`" value=`"jdbc:postgresql://$($newMaster):5432/$DBName`" />"
        Write-Output "<property name=`"url`" value=`"jdbc:postgresql://$($newMaster):5432/$DBName`" />"
        $instanceContext = $instanceContext -replace '<property name="username.+', `
            "<property name=`"username`" value=`"$PGUserName`" />"
        Write-Output "<property name=`"username`" value=`"$PGUserName`" />"
        $instanceContext = $instanceContext -replace '<property name="password.+', `
            "<property name=`"password`" value=`"$env:PGPASSWORD`" />"
        Write-Output "<property name=`"password`" value=`"$env:PGPASSWORD`" />"
        $instanceContext | Out-File -FilePath `
            "Crawler:\apache-tomcat-7.0.40\webapps\unifyle\WEB-INF\classes\instanceContext.xml" -Encoding ascii

        Write-Output "Removing PS Drive Crawler"
        Remove-PSDrive -Name "Crawler"
    }
}


Write-Output "Script $myName Finished`r`n"
