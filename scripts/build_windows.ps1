<#
.SYNOPSIS
  Builds 6browser for Windows and packages it.

.DESCRIPTION
  1. flutter build windows --release
  2. dist/6browser-windows-x64.zip   (portable, always produced)
  3. dist/6browser-setup.exe         (installer, only if Inno Setup's ISCC.exe
                                      is found on PATH or in a default location)

  Requirements: Flutter, CMake, Visual Studio Build Tools (C++ workload).
  Run from anywhere:  powershell -File scripts/build_windows.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$release = Join-Path $root 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

$zip = Join-Path $dist '6browser-windows-x64.zip'
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip
Write-Host "Portable zip: $zip"

$iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    'E:\InnoSetup\ISCC.exe'
  )
  $iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($iscc) {
  & $iscc "/DSourceDir=$release" "/DOutputDir=$dist" (Join-Path $root 'installer\6browser.iss')
  if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
  Write-Host "Installer: $(Join-Path $dist '6browser-setup.exe')"
} else {
  Write-Warning 'Inno Setup not found; skipped the installer. Install it (winget install JRSoftware.InnoSetup) and re-run.'
}
