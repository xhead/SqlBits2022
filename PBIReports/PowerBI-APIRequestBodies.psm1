function Get-ImportRdlBodyRequest($FileName, $RdlFilePath) {
    $Boundary = [guid]::NewGuid().ToString()
    $FileBody = Get-Content -Path $RdlFilePath -Encoding utf8 -Raw
    
    $Body = @"
--FormBoundary$Boundary
Content-Disposition: form-data; name="$FileName"; filename="$FileName"
Content-Type: text/xml

$FileBody
--FormBoundary$Boundary--

"@

    return $body
}

function Get-DataSourceCredentialsBodyRequest ($User, $Password) {
    $Body = @"
    {
        "credentialDetails": {
          "credentialType": "Basic",
          "credentials": "{\"credentialData\":[{\"name\":\"username\", \"value\":\"$User\"},{\"name\":\"password\", \"value\":\"$Password\"}]}",
          "encryptedConnection": "Encrypted",
          "encryptionAlgorithm": "None",
          "privacyLevel": "None"
        }
    }
"@    
    
    return $Body
}

function Get-DataSourceUpdateBodyRequest ($Server, $Database, $DataSource) {
       $Body = @"
  {
    "updateDetails": [
      {
        "datasourceName": "$DataSource",
        "connectionDetails": {
          "server": "$Server",
          "database": "$Database"
        }
      }
    ]
  }
"@ 

    return $Body
}

Export-ModuleMember -Function *
