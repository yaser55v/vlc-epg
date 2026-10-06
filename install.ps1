<#
.SYNOPSIS
  Installs, updates or removes the VLC EPG extension for VLC on Windows.

.EXAMPLE
  irm https://github.com/yaser55v/vlc-epg/releases/latest/download/install.ps1 | iex

.EXAMPLE
  .\install.ps1 -Uninstall
  .\install.ps1 -Uninstall -Purge
#>
param(
  [switch]$Uninstall,
  [switch]$Purge
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'yaser55v/vlc-epg'
$Name = 'vlc_epg.lua'

if ($env:VLC_EPG_URL) { $Url = $env:VLC_EPG_URL } else { $Url = "https://github.com/$Repo/releases/latest/download/$Name" }
if ($env:VLC_EPG_DIR) { $ExtDir = $env:VLC_EPG_DIR } else { $ExtDir = Join-Path $env:APPDATA 'vlc\lua\extensions' }

$DataDir = Split-Path (Split-Path $ExtDir -Parent) -Parent
$Target = Join-Path $ExtDir $Name

if ($Uninstall) {
  if (Test-Path $Target) {
    Remove-Item $Target -Force
    Write-Host "Removed: $Target"
  } else {
    Write-Host "Not installed: $Target"
  }
  if ($Purge) {
    foreach ($f in 'vlc_epg.cfg', 'vlc_epg_cache.txt', 'vlc_epg_download.tmp', 'vlc_epg_download.xml') {
      $p = Join-Path $DataDir $f
      if (Test-Path $p) {
        Remove-Item $p -Force
        Write-Host "Removed: $p"
      }
    }
  }
} else {
  $Tmp = Join-Path ([IO.Path]::GetTempPath()) ('vlc_epg_' + [guid]::NewGuid().ToString('N') + '.lua')
  try {
    Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing
    if (-not (Test-Path $Tmp) -or (Get-Item $Tmp).Length -eq 0) { throw 'The downloaded file is empty.' }
    $Text = Get-Content -Raw -Path $Tmp
    if ($Text -notmatch 'function descriptor') { throw 'The downloaded file is not a VLC extension.' }

    New-Item -ItemType Directory -Force -Path $ExtDir | Out-Null
    Copy-Item -Path $Tmp -Destination $Target -Force

    $Version = ''
    if ($Text -match 'version = "([0-9.]+)"') { $Version = $Matches[1] }
    Write-Host "Installed VLC EPG $Version to: $Target"
    Write-Host ''
    Write-Host 'Next: close VLC completely and open it again.'
    Write-Host 'Then open it from the menu: View > VLC EPG'
  } finally {
    if (Test-Path $Tmp) { Remove-Item $Tmp -Force }
  }
}
