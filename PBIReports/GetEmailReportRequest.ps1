Param (
    [Parameter(Mandatory=$true)][String] $TenantId,
    [Parameter(Mandatory=$true)][String] $ApplicationId,
    [Parameter(Mandatory=$true)][String] $ApplicationSecret,
    [Parameter(Mandatory=$true)][String] $WorkspaceName,
    [Parameter(Mandatory=$true)][String] $DetailedReportName,
    [Parameter(Mandatory=$true)][String] $SummaryReportName,
    [Parameter(Mandatory=$true)][String] $RequestBodyBuildVariableName,
    [Parameter(Mandatory=$true)][String] $EmailToList
)

#YOU CAN COMMENT THIS OUT FOR LOCAL TESTING IF YOU ALREADY INSTALLED THE MODULE. 
Install-Module MicrosoftPowerBIMgmt.Profile -Scope CurrentUser -Force

$Password = ConvertTo-SecureString -String $ApplicationSecret -AsPlainText -Force
$Credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $ApplicationId, $Password
Connect-PowerBIServiceAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential | Out-Null

$WorkspaceList = Invoke-PowerBIRestMethod -Method Get -Url "groups" | ConvertFrom-Json
$WorkspaceId = $WorkspaceList.value | Where-Object { $_.name -eq $WorkspaceName } | Select-Object -First 1 -ExpandProperty "id"

$Reports = Invoke-PowerBIRestMethod -Method Get -Url "groups/$WorkspaceId/reports" | ConvertFrom-Json
$DetailedReport = $Reports.value | Where-Object { $_.name -eq $DetailedReportName } | Select-Object -First 1
$SummaryReport = $Reports.value | Where-Object { $_.name -eq $SummaryReportName } | Select-Object -First 1
$SummaryIsPaginated = $SummaryReport.reportType -eq "PaginatedReport"
$RequestBody = @"
    {
        "WorkspaceId": "$WorkspaceId",
        "DetailedReportId": "$($DetailedReport.id)",
        "SummaryReportId": "$($SummaryReport.id)",
        "WorkspaceName": "$WorkspaceName",
        "DetailedReportName": "$($DetailedReport.name)",
        "SummaryReportName": "$($SummaryReport.name)",
        "EmailToList": "$EmailToList",
        "SummaryIsPaginated": "$SummaryIsPaginated"
    }
"@ | ConvertTo-Json -Compress

###SETS THE AZURE PIPELINE AGENTS BUILD VARIABLE
Write-Host "##vso[task.setvariable variable=$RequestBodyBuildVariableName;]$RequestBody"

###USE THIS FOR TESTING WHEN RUNNIING LOCALLY
# $RequestBody = $RequestBody | ConvertFrom-Json
# $LogicAppUrl = "https://prod-49.northeurope.logic.azure.com:443/workflows/a305eedb4e2a486e9f9c884e16148806/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=Rp2TsEKoax3kt6qbZHHK5RT2ouF3rvir8neIU-4NeZk"
# Invoke-RestMethod -Method POST -Uri $LogicAppUrl -Body $RequestBody -ContentType 'application/json'

