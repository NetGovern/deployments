function GetRandomEclients {
    $chars = [Char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    return (1..127 | ForEach-Object {'{0:X}' -f (Get-Random -InputObject $chars ) }) -join ''
}

function GeneratePassword {
    Param (
        [Parameter()]
        [int]$lenght = 8 #Default lenght
    )
    $chars = [Char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()'
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