Param (
    [Parameter(Mandatory=$true)][String] $WorkspaceName
)

#YOU CAN COMMENT THIS OUT IF YOU ALREADY INSTALLED THE MODULE LOCALLY. 
Install-Module MicrosoftPowerBIMgmt.Profile -Scope CurrentUser -Force
Connect-PowerBIServiceAccount | Out-Null
$Token = Get-PowerBIAccessToken
$BaseUrl = "https://api.powerbi.com/v1.0/myorg"

$WorkspaceList = Invoke-PowerBIRestMethod -Method Get -Url "groups" | ConvertFrom-Json
$WorkspaceId = $WorkspaceList.value | Where-Object { $_.name -eq $WorkspaceName } | Select-Object -First 1 -ExpandProperty "id"

$Reports = Invoke-PowerBIRestMethod -Method Get -Url "groups/$WorkspaceId/reports" | ConvertFrom-Json

$Reports.value | ForEach-Object -Parallel {
    $ReportName = $_.name
    $ReportId = $_.id

    Write-Host "Taking ownership for report: $ReportName"
    Invoke-RestMethod -Method Post -Headers $using:Token -Uri "$using:BaseUrl/groups/$using:WorkspaceId/reports/$ReportId/Default.TakeOver" | Out-Null
}