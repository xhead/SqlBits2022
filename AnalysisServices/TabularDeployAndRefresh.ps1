Param (
    [Parameter(Mandatory=$true)][String] $TenantId,
    [Parameter(Mandatory=$true)][String] $ApplicationId,
    [Parameter(Mandatory=$true)][String] $ApplicationSecret,
    [Parameter(Mandatory=$true)][String] $AnalysisServer,
    [Parameter(Mandatory=$true)][String] $RefreshType,
    [Parameter(Mandatory=$true)][String] $DatabaseName,
    [Parameter(Mandatory=$true)][String] $PathToModel,
    [Parameter(Mandatory=$true)][String] $SqlServer,
    [Parameter(Mandatory=$true)][String] $SqlDatabase,
    [Parameter(Mandatory=$true)][String] $SqlUser,
    [Parameter(Mandatory=$true)][String] $SqlPassword
)

function ApplySQLSecurity($Model, $Server, $Database, $UserName, $Password) {
    $connectionDetails = ConvertFrom-Json '{"connectionDetails":{"protocol":"tds","address":{"server":"server","database":"database"}}}'
    $credential = ConvertFrom-Json '{"credential":{"AuthenticationKind":"UsernamePassword","kind":"kind","path":"server","Username":"user","Password":"pass","EncryptConnection":true}}'
    $dataSources = $Model.model.dataSources
    foreach($dataSource in $dataSources) {
        if ($dataSource.type) {
            $connectionDetails.connectionDetails.protocol = $dataSource.connectionDetails.protocol
            $connectionDetails.connectionDetails.address.server = $Server
            $connectionDetails.connectionDetails.address.database = $Database
            $dataSource.connectionDetails = $connectionDetails.connectionDetails
            $credential.credential.kind = $dataSource.credential.kind
            $credential.credential.EncryptConnection = $dataSource.credential.EncryptConnection
            $credential.credential.AuthenticationKind = $dataSource.credential.AuthenticationKind
            $credential.credential.path = $Server
            $credential.credential.Username = $UserName
            $credential.credential.Password = $Password
            $dataSource.credential = $credential.credential
        }
    }
    return $Model
}

function BuildDatasourceCredentialsRequestBody($User, $Password) {
    $json = '
    {
        "credentialDetails": {
          "credentialType": "Basic",
          "credentials": "{\"credentialData\":[{\"name\":\"username\", \"value\":\"'+$User+'\"},{\"name\":\"password\", \"value\":\"'+$Password+'\"}]}",
          "encryptedConnection": "Encrypted",
          "encryptionAlgorithm": "None",
          "privacyLevel": "None"
        }
    }'
    
    return $json
}

function ParseModelDeploymentMessages($result) {
    $hasErrors = $false
    $resultXml = [Xml]$result
    $messages = $resultXml.return.root.Messages
    
    foreach($message in $messages) {
        $err = $message.Error
        if ($err) {
            $hasErrors = $true
            $errCode = $err.errorcode
            $errMsg = $err.Description
            Write-Error "[Model Deployment Error]:: Code: $errCode, Message: $errMsg)"
        }
        $warn = $message.Warning
        if ($warn) {
            $warnCode = $warn.WarningCode
            $warnMsg = $warn.Description
            Write-Warning "[Model Deployment Warning]:: Code: $warnCode, Message: $warnMsg)"
        }
    }
    return $hasErrors
}

function GetDataset($Token, $BaseUrl, $WorkspaceId, $ModelName) {
    $Datasets = Invoke-RestMethod -Method Get -Headers $Token -Uri "$BaseUrl/groups/$WorkspaceId/datasets"
    $Dataset = $Datasets.value | Where { $_.name -eq $ModelName } | Select -First 1
    return $Dataset
}

Write-Output "Installing PowerBI Management module..."
Install-Module MicrosoftPowerBIMgmt.Profile -Scope CurrentUser -Force

Write-Output "Configuring Credentials..."
$Password = ConvertTo-SecureString -String $ApplicationSecret -AsPlainText -Force
$Credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $ApplicationId, $Password

$IsPowerBi = $AnalysisServer -like "*powerbi://*"
if ($IsPowerBi) { 
    Write-Output "PBI deployment detected. Executing PBI workflows..."

    Write-Output "PBI: Authenticating with PowerBI..."
    Connect-PowerBIServiceAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential | Out-Null
} 
else { 
    Write-Output "AAS deployment detected. Executing AAS workflows..." 
}

Write-Output "Updating model properties..." 
$Model = Get-Content $PathToModel -Encoding UTF8 | ConvertFrom-Json
$Model.name = $DatabaseName
$Model = ($Model | Select-Object -Property * -ExcludeProperty id)

$roles = $Model.model.roles
if ($IsPowerBi) {
    if ($Model.model.roles) {
        Write-Output "PBI: Removing roles from model..."
        $Model.model.roles = @()    
    }
    Write-Output "PBI: Adding V3 datasource version to model..."
    $Model.model | Add-Member -NotePropertyName "defaultPowerBIDataSourceVersion" -NotePropertyValue "powerBI_V3"
} else {
    Write-Output "AAS: Removing memberId's from role members..."
    foreach($role in $roles) {
        if ($role.members) {
            $role.members = @(($role.members | Select-Object -Property * -ExcludeProperty memberId))
        }
    }
}

Write-Output "Building SQL datasource and applying model..."
$Model = ApplySqlSecurity -Model $Model -Server $SqlServer -Database $SqlDatabase -UserName $SqlUser -Password $SqlPassword    

Write-Output "Building TMSL command for deployment..."
$Tmsl = '{"createOrReplace":{"object":{"database":"existingModel"},"database":{"name":"emptyModel"}}}' | ConvertFrom-Json
$Tmsl.createOrReplace.object.database = $DatabaseName
$Tmsl.createOrReplace.database = $Model
$Command = ConvertTo-Json $Tmsl -Depth 100 -Compress

Write-Output "Starting Tabular Model Deployment..."
$ModelDeploymentResult = Invoke-ASCmd -Server $AnalysisServer -Query $Command -ServicePrincipal -ApplicationId $ApplicationId -TenantId $TenantId -Credential $Credential
$ModelDeploymentHasErrors = ParseModelDeploymentMessages -Result $ModelDeploymentResult
if ($ModelDeploymentHasErrors) { Exit }
Start-Sleep 2 #Prevents any additional processing to conflict with PBI API calls
Write-Output "Tabular Model Deployment Completed!"



if ($IsPowerBi) {
    try {
        Write-Output "PBI: Calling RestAPI's to gather data to update datsource credentials on deployed model..."

        $Token = Get-PowerBIAccessToken
        $BaseUrl = "https://api.powerbi.com/v1.0/myorg"
        
        $WorkspaceName = $AnalysisServer.Substring($AnalysisServer.IndexOf("myorg") + 6)

        Write-Output "PBI: Fetching workspaceId for $WorkspaceName..."
        $GroupsResponse = Invoke-RestMethod -Method Get -Headers $Token -Uri "$BaseUrl/groups"
        $Workspace = $GroupsResponse.value | Where { $_.name -eq $WorkspaceName } | Select -First 1
        
        Write-Output "PBI: Fetching dataset for takeover..."
        $Dataset = GetDataset -Token $Token -BaseUrl $BaseUrl -WorkspaceId $Workspace.id -ModelName $Model.name

        Invoke-RestMethod -Method Post -Headers $Token -Uri "$BaseUrl/groups/$($Workspace.id)/datasets/$($Dataset.id)/Default.TakeOver" | Out-Null

        Write-Output "PBI: Fetching dataset for datasource update..."
        $Dataset = GetDataset -Token $Token -BaseUrl $BaseUrl -WorkspaceId $Workspace.id -ModelName $Model.name
        
        Write-Output "PBI: Fetching datasource for datasource update..."
        $Datasources = Invoke-RestMethod -Method Get -Headers $Token -Uri "$BaseUrl/groups/$($Workspace.id)/datasets/$($Dataset.id)/datasources"
        $Datasource = $Datasources.value | Select -First 1

        Write-Output "PBI: Published model identifiers..."
        Write-Output "PBI: ModelName: '$($Model.name)'"
        Write-Output "PBI: WorkspaceId: '$($Workspace.id)'"
        Write-Output "PBI: DatasetId: '$($Dataset.id)'"
        Write-Output "PBI: DatasourceId: '$($Datasource.datasourceId)'"
        Write-Output "PBI: GatewayId: '$($Datasource.gatewayId)'"
        
        $CredentialsRequest = BuildDatasourceCredentialsRequestBody -User $SqlUser -Password $SqlPassword | ConvertFrom-Json | ConvertTo-Json

        Write-Output "PBI: Updating datasource credentials..."
        Invoke-RestMethod -Method Patch -Body $CredentialsRequest -Headers $Token -ContentType "application/json" -Uri "$BaseUrl/gateways/$($Datasource.gatewayId)/datasources/$($Datasource.datasourceId)" | Out-Null        
        Write-Output "PBI: Credentials update completed!"
    }
    catch {
        $ex = $_
        try {
			Write-Output "Attempting to extract response stream from HTTPResponse..."
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            Write-Error $reader.ReadToEnd()
        } catch {
			Write-Output "No response stream.  Throwing original exception..."
            Write-Error $ex
        }
    }
}

if ($RefreshType -ne "None") {
    Write-Output "Starting model refresh with type: '$($RefreshType)'..."
    Invoke-ProcessASDatabase -Server $AnalysisServer -DatabaseName $DatabaseName -RefreshType $RefreshType -ServicePrincipal -ApplicationId $ApplicationId -TenantId $TenantId -Credential $Credential
    Write-Output "RefreshType: '$($RefreshType)' Completed!..."
} else {
    Write-Warning "RefreshType set to 'None'. Tabular model will not process."
}

