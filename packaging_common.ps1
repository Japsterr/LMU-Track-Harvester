function Resolve-BrandingIconPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root
  )

  $iconPath = Join-Path $Root 'branding\app-icon.ico'
  if (Test-Path $iconPath) {
    return $iconPath
  }

  return $null
}

function Resolve-SignToolPath {
  param(
    [string]$ConfiguredPath
  )

  if ($ConfiguredPath -and (Test-Path $ConfiguredPath)) {
    return $ConfiguredPath
  }

  $command = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $windowsKitsDir = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
  if (Test-Path $windowsKitsDir) {
    $candidate = Get-ChildItem $windowsKitsDir -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($candidate) {
      return $candidate.FullName
    }
  }

  return $null
}

function Invoke-CodeSigning {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Files,

    [switch]$Sign,
    [string]$SignToolPath,
    [string]$CertificateThumbprint,
    [string]$CertificatePath,
    [string]$CertificatePassword,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
  )

  if (-not $Sign) {
    Write-Warning 'Artifacts are unsigned. Windows Defender and SmartScreen may flag unsigned EXEs and installers even when they are clean.'
    return
  }

  $resolvedSignTool = Resolve-SignToolPath -ConfiguredPath $SignToolPath
  if (-not $resolvedSignTool) {
    throw 'Signing was requested, but signtool.exe was not found. Set SIGNTOOL_PATH or install the Windows SDK signing tools.'
  }

  if (-not $CertificateThumbprint -and -not $CertificatePath) {
    throw 'Signing was requested, but no certificate was configured. Set CODESIGN_CERT_THUMBPRINT or CODESIGN_PFX_PATH.'
  }

  foreach ($file in $Files) {
    if (-not (Test-Path $file)) {
      throw "Signing target not found: $file"
    }

    $arguments = @(
      'sign'
      '/fd', 'sha256'
    )

    if ($TimestampUrl) {
      $arguments += @('/tr', $TimestampUrl, '/td', 'sha256')
    }

    if ($CertificatePath) {
      $arguments += @('/f', $CertificatePath)
      if ($CertificatePassword) {
        $arguments += @('/p', $CertificatePassword)
      }
    } else {
      $arguments += @('/sha1', $CertificateThumbprint)
    }

    $arguments += $file
    & $resolvedSignTool @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "signtool failed for $file"
    }
  }
}