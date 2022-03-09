Param (
  [Parameter(Mandatory=$true)][String] $Directory,
  [Parameter(Mandatory=$true)][String] $BuildConfiguration
)

Write-Output "Searching for reporting projects in '$Directory'..."
$ProjectFiles = Get-ChildItem -Path $Directory\*.rptproj -Recurse
$ProjectCount = $ProjectFiles.Count
Write-Output "$ProjectCount Projects found."

$ProjectFiles | ForEach-Object {
  $ProjectName = Split-Path $_ -Leaf
  $ProjectPath = Split-Path $_
  $BinPath = "$ProjectPath\bin\$BuildConfiguration"

  Write-Output "Copying '$ProjectName' to '$BinPath'..."
  Copy-Item $_ -Destination $BinPath
}

Write-Output "Project copy completed!"