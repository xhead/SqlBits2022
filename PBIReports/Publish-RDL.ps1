Param (
    [Parameter(Mandatory=$true)][String] $TenantId,
    [Parameter(Mandatory=$true)][String] $ApplicationId,
    [Parameter(Mandatory=$true)][String] $ApplicationSecret,
    [Parameter(Mandatory=$true)][String] $WorkspaceName,
    [Parameter(Mandatory=$true)][String] $ProjectPath,
    [Parameter(Mandatory=$true)][String] $DataSource,
    [Parameter(Mandatory=$true)][String] $SqlServer,
    [Parameter(Mandatory=$true)][String] $SqlDatabase,
    [Parameter(Mandatory=$true)][String] $SqlUser,
    [Parameter(Mandatory=$true)][String] $SqlPassword,
    [Parameter(Mandatory=$false)][String] $ReportNamePrefix = ""

)

Write-Host "Authenticating with PowerBI via Service Principal"
 Install-Module MicrosoftPowerBIMgmt.Profile -Scope CurrentUser -Force
$Password = ConvertTo-SecureString -String $ApplicationSecret -AsPlainText -Force
$Credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $ApplicationId, $Password
Connect-PowerBIServiceAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential | Out-Null
$Token = Get-PowerBIAccessToken
$BaseUrl = "https://api.powerbi.com/v1.0/myorg"

Write-Host "Loading metadata from reporting project"            
$ProjectRoot = $ProjectPath | Split-Path
[xml]$Project = Get-Content -Path $ProjectPath
$xmlnsValue = $Project.DocumentElement.Attributes["xmlns"].Value
[System.Xml.XmlNameSpaceManager] $xmlns = new-object -TypeName System.Xml.XmlNameSpaceManager -ArgumentList $Project.NameTable
$xmlns.AddNamespace("msb", $xmlnsValue)

Write-Host "Fetching workspace '$WorkspaceName' identifier"
$WorkspaceList = Invoke-PowerBIRestMethod -Method Get -Url "groups" | ConvertFrom-Json
$WorkspaceId = $WorkspaceList.value | Where-Object { $_.name -eq $WorkspaceName } | Select-Object -First 1 -ExpandProperty "id"

Write-Host "Fetching report list from workspace $WorkspaceName"
$Reports = Invoke-PowerBIRestMethod -Method Get -Url "groups/$WorkspaceId/reports" | ConvertFrom-Json

$ScriptRoot = $PSScriptRoot
Write-Host "Starting parallel report deployment"
$Project.SelectNodes("//msb:Report", $xmlns) | ForEach-Object -Parallel {

  Import-Module "$using:ScriptRoot\PowerBI-APIRequestBodies.psm1"
  $FileName = $_.Include
  $RdlPath = $using:ProjectRoot | join-path -ChildPath $FileName
  $FileNameNoExt = [IO.Path]::GetFileNameWithoutExtension($RdlPath)
  $ReportName = "$using:ReportNamePrefix$FileNameNoExt"
  $ReportId = $using:Reports.value | Where-Object { $_.name -eq $ReportName } | Select-Object -First 1 -ExpandProperty "id"

  [xml]$ReportXml = Get-Content -Path $RdlPath
  $ReportXmlnsValue = $ReportXml.DocumentElement.Attributes["xmlns"].Value
  [System.Xml.XmlNameSpaceManager] $ReportXmlns = new-object -TypeName System.Xml.XmlNameSpaceManager -ArgumentList $ReportXml.NameTable
  $ReportXmlns.AddNamespace("msb", $ReportXmlnsValue)
  $ReportXml.SelectNodes("//msb:ReportName", $ReportXmlns) | ForEach-Object {
    $_."#text" = "$using:ReportNamePrefix$($_."#text")"
  }
  $ReportXml.Save($RdlPath)
   
  $PublishMessage = "Publishing RDL"
  try {
    Write-Host "[1/4:STARTED:$ReportName] - $PublishMessage"
    $ConflictType = "Abort"
    if ($ReportId) { $ConflictType = "Overwrite" }
    $ImportRdlRequest = Get-ImportRdlBodyRequest -FileName $FileName -RdlFilePath $RdlPath
    Invoke-RestMethod -Method Post -Body $ImportRdlRequest -ContentType "multipart/form-data" -Headers $using:Token -Uri "$using:BaseUrl/groups/$using:WorkspaceId/imports?datasetDisplayName=$ReportName.rdl&nameConflict=$ConflictType" | Out-Null
    Write-Host "[1/4:DONE:$ReportName] - $PublishMessage" -ForegroundColor Green
    Start-Sleep 1 #Processing still occurs server side after we get a response from importing.
  } catch {
    Write-Host "[1/4:FAILED:$ReportName] - $PublishMessage" -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Error $_
    Write-Host "[EXITING SCRIPT:$ReportName]" -ForegroundColor Black -BackgroundColor DarkYellow
    Exit
  }

  $UpdateDataSourceMessage = "Updating datasource"
  try {
    Write-Host "[2/4:STARTED:$ReportName] - $UpdateDataSourceMessage"
    if ($ReportId -eq $null) {
      $ReloadedReports = Invoke-PowerBIRestMethod -Method Get -Url "groups/$using:WorkspaceId/reports" | ConvertFrom-Json
      $ReportId = $ReloadedReports.value | Where-Object { $_.name -eq $ReportName } | Select-Object -First 1 -ExpandProperty "id"
    }
    $DatasourceRequest = Get-DataSourceUpdateBodyRequest -Server $using:SqlServer -Database $using:SqlDatabase -DataSource $using:DataSource
    Invoke-RestMethod -Method Post -Body $DatasourceRequest -Headers $using:Token -ContentType "application/json" -Uri "$using:BaseUrl/groups/$using:WorkspaceId/reports/$ReportId/Default.UpdateDatasources" | Out-Null
    Write-Host "[2/4:DONE:$ReportName] - $UpdateDataSourceMessage" -ForegroundColor Green
  } catch {
    Write-Host "[2/4:FAILED:$ReportName] - $UpdateDataSourceMessage" -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Error $_
    Write-Host "[EXITING SCRIPT:$ReportName]" -ForegroundColor Black -BackgroundColor DarkYellow
    Exit
  }

  $FetchDataSourceMessage = "Fetching datasource to obtain identifier and gateway"
  try {
    Write-Host "[3/4:STARTED:$ReportName] - $FetchDataSourceMessage"
    $Datasources = Invoke-RestMethod -Method Get -Headers $using:Token -Uri "$using:BaseUrl/groups/$using:WorkspaceId/reports/$ReportId/datasources"
    $Datasource = $Datasources[0].value
    Write-Host "[3/4:DONE:$ReportName] - $FetchDataSourceMessage" -ForegroundColor Green
  } catch {
    Write-Host "[3/4:FAILED:$ReportName] - $FetchDataSourceMessage" -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Error $_
    Write-Host "[EXITING SCRIPT:$ReportName]" -ForegroundColor Black -BackgroundColor DarkYellow
    Exit
  }

  $UpdateCredentialsMessage = "Updating credentials on datasource"
  $IsTabular = $using:SqlServer -Like "*asazure://*"
  try {
    if ($IsTabular) {
      Write-Host "[4/4:SKIPPED:$ReportName] - $UpdateCredentialsMessage not required for tabular connection"
      Exit
    }
    Write-Host "[4/4:STARTED:$ReportName] - $UpdateCredentialsMessage"
    $CredentialsBody = Get-DataSourceCredentialsBodyRequest -User $using:SqlUser -Password $using:SqlPassword
    Invoke-RestMethod -Method Patch -Body $CredentialsBody -Headers $using:Token -ContentType "application/json" -Uri "$using:BaseUrl/gateways/$($Datasource.gatewayId)/datasources/$($Datasource.datasourceId)" | Out-Null
    Write-Host "[4/4:DONE:$ReportName] - $UpdateCredentialsMessage" -ForegroundColor Green
  } catch {
    Write-Host "[4/4:FAILED:$ReportName] - $UpdateCredentialsMessage" -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Error $_
    Write-Host "[EXITING SCRIPT:$ReportName]" -ForegroundColor Black -BackgroundColor DarkYellow
    Exit
  }
}

Write-Host "Deployment Complete!" -ForegroundColor Green
