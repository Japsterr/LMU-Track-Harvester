param(
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release',

  [ValidateSet('Win32')]
  [string]$Platform = 'Win32'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $root 'dist'
$downloadDir = Join-Path $root 'download'
$stageDir = Join-Path $distDir "LMUTrackHarvester-$Platform-$Configuration"
$portableZip = Join-Path $distDir "LMUTrackHarvester-$Platform-$Configuration-portable.zip"
$installerWorkDir = Join-Path $distDir 'installer-work'
$payloadZip = Join-Path $installerWorkDir 'payload.zip'
$installerSource = Join-Path $installerWorkDir 'InstallerStub.cs'
$installerExe = Join-Path $downloadDir 'LMUTrackHarvester-Installer.exe'
$downloadZip = Join-Path $downloadDir 'LMUTrackHarvester-Portable.zip'
$cscPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$bundledPythonPath = $null

foreach ($candidatePath in @(
  (Join-Path $root 'python'),
  (Join-Path $root 'runtime\python')
)) {
  if (Test-Path (Join-Path $candidatePath 'python.exe')) {
    $bundledPythonPath = $candidatePath
    break
  }
}

& (Join-Path $root 'bundle_release.ps1') -Configuration $Configuration -Platform $Platform

if (-not (Test-Path $stageDir)) {
  throw "Stage directory not found: $stageDir"
}

if (Test-Path $installerWorkDir) {
  Remove-Item $installerWorkDir -Recurse -Force
}

New-Item -ItemType Directory -Path $installerWorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $payloadZip -CompressionLevel Optimal

$installerSourceContent = @'
using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

internal static class Program
{
  [STAThread]
  private static void Main()
  {
    var installDir = Path.Combine(
      Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
      "Programs",
      "LMU Track Harvester");

    Directory.CreateDirectory(installDir);

    var tempZip = Path.Combine(Path.GetTempPath(), "LMUTrackHarvester-payload.zip");
    using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Payload.zip"))
    {
      if (resource == null)
      {
        MessageBox.Show("Installer payload was not found.", "LMU Track Harvester Installer",
          MessageBoxButtons.OK, MessageBoxIcon.Error);
        return;
      }

      using (var file = File.Create(tempZip))
      {
        resource.CopyTo(file);
      }
    }

    try
    {
      if (Directory.Exists(installDir))
      {
        Directory.Delete(installDir, true);
      }

      Directory.CreateDirectory(installDir);
      ZipFile.ExtractToDirectory(tempZip, installDir);
      var exePath = Path.Combine(installDir, "LMUTrackHarvester.exe");
      if (!File.Exists(exePath))
      {
        MessageBox.Show("Install completed but the app executable was not found.",
          "LMU Track Harvester Installer", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        return;
      }

      MessageBox.Show("LMU Track Harvester was installed to:\n\n" + installDir,
        "LMU Track Harvester Installer", MessageBoxButtons.OK, MessageBoxIcon.Information);
      System.Diagnostics.Process.Start(exePath);
    }
    catch (Exception ex)
    {
      MessageBox.Show(ex.Message, "LMU Track Harvester Installer",
        MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
    finally
    {
      if (File.Exists(tempZip))
        File.Delete(tempZip);
    }
  }
}
'@
Set-Content -Path $installerSource -Value $installerSourceContent -Encoding ASCII

if (Test-Path $installerExe) {
  Remove-Item $installerExe -Force
}

if (-not (Test-Path $cscPath)) {
  throw "C# compiler not found: $cscPath"
}

$cscArgs = @(
  '/nologo'
  '/target:winexe'
  '/optimize+'
  "/out:$installerExe"
  "/resource:$payloadZip,Payload.zip"
  '/reference:System.IO.Compression.FileSystem.dll'
  '/reference:System.Windows.Forms.dll'
  $installerSource
)

& $cscPath @cscArgs | Out-Null

if (-not (Test-Path $installerExe)) {
  throw "Installer was not created: $installerExe"
}

Copy-Item $portableZip $downloadZip -Force

Write-Host "Download artifacts created:"
Write-Host "  Installer: $installerExe"
Write-Host "  Portable : $downloadZip"
if ($bundledPythonPath) {
  Write-Host "  Python   : bundled from $bundledPythonPath"
  Write-Host "  Support  : LMU DuckDB export and metadata helpers are portable for testers without Python installed."
} else {
  Write-Warning "No portable Python runtime was bundled."
  Write-Warning "The installer and zip will run the app, but LMU DuckDB helper features still need Python plus duckdb on the tester machine."
}