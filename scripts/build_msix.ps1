<#
.SYNOPSIS
  Packages the Windows release build as an MSIX for the Microsoft Store.

.DESCRIPTION
  1. Uses build\windows\x64\runner\Release (run `flutter build windows --release`
     first, or pass -Build).
  2. Writes AppxManifest.xml, tile images and resources.pri.
  3. dist\6browser-<version>-x64.msix, signed with -PfxPath if given.

  For a Store upload, -IdentityName, -Publisher and -PublisherDisplayName must
  be the values from Partner Center > your app > Product identity. The Store
  re-signs the package, so the signature only matters for local installs.

.EXAMPLE
  powershell -File scripts/build_msix.ps1 -PfxPath E:\6browser-signing\6arshid-msix.pfx -PfxPassword ...
#>
param(
  [string]$IdentityName = '6arshid.6browser',
  [string]$Publisher = 'CN=44315FA5-4878-44FB-9167-723357EE983C',
  [string]$PublisherDisplayName = '6arshid',
  [string]$DisplayName = '6browser',
  [string]$Version,
  [string]$PfxPath,
  [string]$PfxPassword,
  [switch]$Build
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($Build) {
  # CEF with proprietary codecs (H.264/AAC, needed for YouTube live), built from
  # source; see docs/ENGINE.md. Without it the CDN build (no H.264/AAC) is used.
  if (-not $env:CEF_CUSTOM_DISTRIB -and (Test-Path 'E:\6browser-cef\cef_codecs')) {
    $env:CEF_CUSTOM_DISTRIB = 'E:\6browser-cef\cef_codecs'
  }
  if ($env:CEF_CUSTOM_DISTRIB) { Write-Host "CEF: $env:CEF_CUSTOM_DISTRIB" }

  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

# MSIX versions are four numbers; take major.minor.patch from pubspec.yaml.
if (-not $Version) {
  $line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\d+)\.(\d+)\.(\d+)' | Select-Object -First 1
  $m = $line.Matches[0].Groups
  $Version = "$($m[1].Value).$($m[2].Value).$($m[3].Value).0"
}

$kits = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*\x64\makeappx.exe" |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $kits) { throw 'Windows 10/11 SDK (makeappx.exe) not found' }
$sdk = $kits.DirectoryName
$makeappx = Join-Path $sdk 'makeappx.exe'
$makepri = Join-Path $sdk 'makepri.exe'
$signtool = Join-Path $sdk 'signtool.exe'

$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release '6browser.exe'))) {
  throw "No release build in $release; run with -Build"
}

$stage = Join-Path $root 'build\msix\stage'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item -Recurse (Join-Path $release '*') $stage

python (Join-Path $PSScriptRoot 'msix_assets.py') (Join-Path $stage 'Assets')
if ($LASTEXITCODE -ne 0) { throw 'msix_assets.py failed' }

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">
  <Identity Name="$IdentityName" Publisher="$Publisher" Version="$Version" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$DisplayName</DisplayName>
    <PublisherDisplayName>$PublisherDisplayName</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Applications>
    <Application Id="SixBrowser" Executable="6browser.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="$DisplayName"
        Description="Fast, lightweight web browser"
        BackgroundColor="transparent"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" ShortName="6browser" />
      </uap:VisualElements>
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="internetClient" />
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@
Set-Content -Path (Join-Path $stage 'AppxManifest.xml') -Value $manifest -Encoding utf8

# Index the scale/targetsize image variants.
$priConfig = Join-Path $root 'build\msix\priconfig.xml'
& $makepri createconfig /cf $priConfig /dq en-US /pv 10.0.0 /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'makepri createconfig failed' }
# One resources.pri: split scale/language packs only work in a bundle.
$cfg = [xml](Get-Content $priConfig)
$pk = $cfg.SelectSingleNode('//packaging')
if ($pk) { [void]$pk.ParentNode.RemoveChild($pk) }
$cfg.Save($priConfig)
& $makepri new /pr $stage /cf $priConfig /mn (Join-Path $stage 'AppxManifest.xml') /of (Join-Path $stage 'resources.pri') /o
if ($LASTEXITCODE -ne 0) { throw 'makepri new failed' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$msix = Join-Path $dist "6browser-$Version-x64.msix"
& $makeappx pack /d $stage /p $msix /o
if ($LASTEXITCODE -ne 0) { throw 'makeappx failed' }

if ($PfxPath) {
  & $signtool sign /fd SHA256 /f $PfxPath /p $PfxPassword $msix
  if ($LASTEXITCODE -ne 0) { throw 'signtool failed (the certificate subject must equal -Publisher)' }
}
Write-Host "MSIX: $msix"
