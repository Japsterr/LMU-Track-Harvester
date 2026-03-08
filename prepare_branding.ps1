param(
  [string]$IconPath,
  [string]$OutputResource,
  [string]$Brcc32Path
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$brandingDir = Join-Path $root 'branding'

if (-not $IconPath) {
  $IconPath = Join-Path $brandingDir 'app-icon.ico'
}

if (-not (Test-Path $IconPath)) {
  throw "Branding icon not found: $IconPath"
}

if (-not $OutputResource) {
  $OutputResource = Join-Path $root 'LMUTrackHarvester.res'
}

if (-not $Brcc32Path) {
  $command = Get-Command 'brcc32.exe' -ErrorAction SilentlyContinue
  if ($command) {
    $Brcc32Path = $command.Source
  }
}

if (-not $Brcc32Path) {
  throw 'brcc32.exe was not found. Open the RAD Studio command prompt or add brcc32.exe to PATH before preparing branding resources.'
}

$iconFileName = Split-Path $IconPath -Leaf
$resourceScript = Join-Path $brandingDir 'app-icon.rc'
$resourceScriptContent = 'MAINICON ICON "' + $iconFileName + '"'
Set-Content -Path $resourceScript -Value $resourceScriptContent -Encoding ASCII

Push-Location $brandingDir
try {
  & $Brcc32Path ("-fo{0}" -f $OutputResource) $resourceScript
  if ($LASTEXITCODE -ne 0) {
    throw 'brcc32.exe failed to compile the application icon resource.'
  }
} finally {
  Pop-Location
}

if (-not (Test-Path $OutputResource)) {
  throw "Expected branding resource was not created: $OutputResource"
}

Write-Host "Updated project icon resource: $OutputResource"