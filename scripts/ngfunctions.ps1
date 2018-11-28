function TestLDAPConn {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$ldap_server,
        [Parameter(Mandatory = $True)]
        [string]$ldap_admin_dn,
        [Parameter(Mandatory = $True)]
        [string]$ldap_admin_password,
        [Parameter()]
        [switch]$ssl

    )

    [System.Environment]::SetEnvironmentVariable("LDAPTLS_REQCERT","never")
    $ldap_whoami = "$env:NETMAIL_BASE_DIR\openldap\ldapwhoami.exe"
    if ($ssl) {
        $ldap_uri = "ldaps://$ldap_server"
    } else {
        $ldap_uri = "ldap://$ldap_server"
    }
    
    $test_ldap_conn = @(
        "-vvv", 
        "-H", 
        $ldap_uri, 
        "-D", 
        $ldap_admin_dn, 
        "-x", 
        "-w", 
        $ldap_admin_password
    )

    $p = Start-Process -FilePath $ldap_whoami -ArgumentList $test_ldap_conn -Wait -NoNewWindow -PassThru
    return $p.ExitCode
}

function ParseEdirProperties {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$edir_properties_path
    )
    $ldap_settings = @{}
    $edir_properties = Get-Content "$edir_properties_path"
    $ldap_settings['host'] = (($edir_properties | Select-String 'edir.host=').Line -split '=', 2)[1]
    $ldap_settings['port'] = (($edir_properties | Select-String 'edir.port=').Line -split '=', 2)[1]
    $ldap_settings['logindn'] = (($edir_properties | Select-String 'edir.logindn=').Line -split '=',2)[1]
    $ldap_settings['loginpwdclear'] = (($edir_properties | Select-String 'edir.loginpwdclear=').Line -split '=',2)[1]
    $ldap_settings['edir_container'] = (($edir_properties | Select-String 'edir.container=').Line -split '=', 2)[1]
    $ldap_settings['tenant_id'] = [regex]::match($ldap_settings['edir_container'], ".o=(.*?),o=netmail").Groups[1].Value
    return $ldap_settings
}
function ParseSQLConnString {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$db_conn_string
    )
    $db_conn_array = $db_conn_string -split ';'
    $db_conn_array = $db_conn_array[0..($db_conn_array.count - 2)]

    $db_conn_object = @{}
    $db_conn_array | foreach {
        if ($_.tostring().contains('=')) {
            $db_conn_object[($_ -split "=")[0].ToLower()] = ($_ -split "=")[1]
        }
        else {
            $db_conn_object['port'] = $_
        }
    }
    return $db_conn_object
}
function GetRandomEclients {
    $chars = [Char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    return (1..127 | ForEach-Object {'{0:X}' -f (Get-Random -InputObject $chars ) }) -join ''
}

function GeneratePassword {
    Param (
        [Parameter()]
        [int]$lenght = 8 #Default lenght
    )
    $chars = [Char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    return (1..$lenght | ForEach-Object {'{0:X}' -f (Get-Random -InputObject $chars ) }) -join ''
}
function GetTimeLdapFormat {
    $utc_time = Get-Date
    return $utc_time.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss:fffZ")
}

function DecodeBase64 {
    Param(
        [Parameter(Mandatory=$True)]
        [string]$value
	
    )
    return [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($value))  
}

function EncodeBase64 {
    Param(
        [Parameter(Mandatory=$True)]
        [string]$value
	
    )
    return [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($value))
}

function HashForLDAP {
    Param(
        [Parameter(Mandatory=$True)]
        [string]$password
	
    )
    return (& $env:NETMAIL_BASE_DIR\openldap\slappasswd.exe -s $password)
}

function TokenReplacement {
   Param(
       [Parameter(Mandatory=$True)]
        [string]$tokenized_content,
       [Parameter(Mandatory=$True)]
       [hashtable]$token_collection
    )
    $token_collection.keys | ForEach-Object { 
        $token_to_replace = "[" + $_ + "]"
        $tokenized_content = $tokenized_content.Replace($token_to_replace,$token_collection[$_])
    }
    return $tokenized_content
}

function EncodeBase64InFile {
    Param(
        [Parameter(Mandatory = $True)]
        [array]$content_to_encode
    )
    
    $new_lines = @()
    foreach ($line in $content_to_encode) {
        if ($line.Contains("encode_me")) {
            $encoded_line = ($line -split "encode_me")[0]
            $encoded_line = $encoded_line + (EncodeBase64 -value (($line -split "encode_me")[1]))
            $new_lines += $encoded_line
        }
        else {
            $new_lines += $line
        }
    }
    return $new_lines
}

function Write-Log {
    param (
        [Parameter()]
        [string]$Message,
        [Parameter()]
        [string]$logFilePath,
        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Severity = "INFO" ## Default to a low severity.
    )
    
    if ( [string]::IsNullOrEmpty($Message) ) {
        $Message = "No output"
    }

    if ( [string]::IsNullOrEmpty($logFilePath) ) {
        $logFilePath = ".\DefaultLog.txt"
    }

    $line = (Get-Date).ToString() + " -- [ $Severity ] -- $Message"
    
    if ( !(Test-Path -Path $logFilePath -PathType Leaf) ) {
        Set-Content -Path $logFilePath -Value $line
    } else {
        Add-Content -Path $logFilePath -Value $line
    }
}

function Output-Nice-Xml ([xml]$xml) {
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
    $XmlWriter.Formatting = "indented";
    $xml.WriteTo($XmlWriter);
    $XmlWriter.Flush();
    $StringWriter.Flush();
    Write-Output $StringWriter.ToString();
}