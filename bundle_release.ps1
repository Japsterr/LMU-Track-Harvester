param(
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release',

  [ValidateSet('Win64')]
  [string]$Platform = 'Win64',

  [string]$OutputZip,

  [switch]$Sign,
  [string]$SignToolPath = $env:SIGNTOOL_PATH,
  [string]$CertificateThumbprint = $env:CODESIGN_CERT_THUMBPRINT,
  [string]$CertificatePath = $env:CODESIGN_PFX_PATH,
  [string]$CertificatePassword = $env:CODESIGN_PFX_PASSWORD,
  [string]$TimestampUrl = $(if ($env:CODESIGN_TIMESTAMP_URL) { $env:CODESIGN_TIMESTAMP_URL } else { 'http://timestamp.digicert.com' })
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'packaging_common.ps1')

$buildDir = Join-Path $root "$Platform\$Configuration"
$exePath = Join-Path $buildDir 'LMUTrackHarvester.exe'

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

$duckdbDllPath = Join-Path $root 'duckdb.dll'
if (Test-Path $duckdbDllPath) {
  Copy-Item $duckdbDllPath $stageDir -Force
} else {
  Write-Warning 'duckdb.dll was not found in the repository root. LMU source .duckdb browsing and export will be unavailable in this build.'
}

Copy-Item (Join-Path $root 'README.md') $stageDir -Force

Invoke-CodeSigning -Files @(Join-Path $stageDir 'LMUTrackHarvester.exe') -Sign:$Sign -SignToolPath $SignToolPath -CertificateThumbprint $CertificateThumbprint -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -TimestampUrl $TimestampUrl

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $OutputZip -CompressionLevel Optimal

Write-Host "Portable bundle created: $OutputZip"
if (Test-Path $duckdbDllPath) {
  Write-Host 'DuckDB runtime bundled: duckdb.dll'
  Write-Host 'LMU source .duckdb metadata and CSV export will work without Python.'
}