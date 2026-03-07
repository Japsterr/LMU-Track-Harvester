param(
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release',

  [ValidateSet('Win32')]
  [string]$Platform = 'Win32',

  [string]$OutputZip
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $root "$Platform\$Configuration"
$exePath = Join-Path $buildDir 'LMUTrackHarvester.exe'
$bundledPythonPath = $null

if (-not (Test-Path $exePath)) {
  $exePath = Join-Path $root 'LMUTrackHarvester.exe'
  $buildDir = $root
}

if (-not (Test-Path $exePath)) {
  throw "Build output not found in either $buildDir or the repository root."
}

$distDir = Join-Path $root 'dist'
$stageDir = Join-Path $distDir "LMUTrackHarvester-$Platform-$Configuration"

if (-not $OutputZip) {
  $OutputZip = Join-Path $distDir "LMUTrackHarvester-$Platform-$Configuration-portable.zip"
}

if (Test-Path $stageDir) {
  Remove-Item $stageDir -Recurse -Force
}

if (Test-Path $OutputZip) {
  Remove-Item $OutputZip -Force
}

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

if ($buildDir -eq $root) {
  Get-ChildItem $buildDir -File | Where-Object {
    ($_.Extension -in '.exe', '.dll', '.bpl', '.manifest') -and
    ($_.Name -notin 'VerifyResultsImport.exe')
  } | ForEach-Object {
    Copy-Item $_.FullName $stageDir -Force
  }
} else {
  Copy-Item (Join-Path $buildDir '*') $stageDir -Recurse -Force
}

$scriptsSource = Join-Path $root 'scripts'
$scriptsTarget = Join-Path $stageDir 'scripts'
New-Item -ItemType Directory -Path $scriptsTarget -Force | Out-Null
Get-ChildItem $scriptsSource -Force | Where-Object { $_.Name -ne '__pycache__' } | ForEach-Object {
  Copy-Item $_.FullName $scriptsTarget -Recurse -Force
}

Copy-Item (Join-Path $root 'README.md') $stageDir -Force

$portablePythonPaths = @(
  (Join-Path $root 'python'),
  (Join-Path $root 'runtime\python')
)

foreach ($portablePythonPath in $portablePythonPaths) {
  $pythonExe = Join-Path $portablePythonPath 'python.exe'
  if (Test-Path $pythonExe) {
    if (-not $bundledPythonPath) {
      $bundledPythonPath = $portablePythonPath
    }

    $targetFolder = if ((Split-Path $portablePythonPath -Leaf) -ieq 'python') {
      Join-Path $stageDir 'python'
    } else {
      Join-Path $stageDir 'runtime\python'
    }

    New-Item -ItemType Directory -Path (Split-Path $targetFolder -Parent) -Force | Out-Null
    Copy-Item $portablePythonPath $targetFolder -Recurse -Force
  }
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $OutputZip -CompressionLevel Optimal

Write-Host "Portable bundle created: $OutputZip"
if ($bundledPythonPath) {
  Write-Host "Portable Python bundled from: $bundledPythonPath"
  Write-Host "LMU DuckDB helper scripts will work on tester machines without a separate Python install."
} else {
  Write-Warning "No bundled portable Python runtime was found under 'python\' or 'runtime\python\'."
  Write-Warning "The app bundle is still usable, but LMU DuckDB helper features will require Python plus duckdb on the tester machine."
}