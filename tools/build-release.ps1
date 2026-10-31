# Stellt das Release-ZIP zusammen: lädt otvdm, oggenc2 und Magpie, baut bei Bedarf die winmm.dll
param([string]$Version = '1.0')

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$d    = Join-Path $root 'dateien'
$tmp  = Join-Path $root 'build\downloads'
New-Item -ItemType Directory -Force $tmp | Out-Null

function Get-Zip([string]$url, [string]$name) {
    $zip = Join-Path $tmp "$name.zip"
    if (-not (Test-Path $zip)) { Invoke-WebRequest $url -OutFile $zip }
    $out = Join-Path $tmp $name
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    Expand-Archive $zip $out
    return $out
}

if (-not (Test-Path "$d\otvdm\otvdmw.exe")) {
    $x = Get-Zip 'https://github.com/otya128/winevdm/releases/download/v0.9.0/otvdm-v0.9.0.zip' 'otvdm'
    Move-Item (Get-ChildItem $x -Directory | Select-Object -First 1).FullName "$d\otvdm"
    # Registrierungs-Helfer von otvdm werden nicht gebraucht – der Patch nutzt eine private Kopie
    Remove-Item "$d\otvdm\install*.lnk", "$d\otvdm\install*.inf", "$d\otvdm\uninstall.reg" -Force
}
if (-not (Test-Path "$d\oggenc2.exe")) {
    $x = Get-Zip 'https://www.rarewares.org/files/ogg/oggenc2.88-1.3.7-generic.zip' 'oggenc2'
    Copy-Item (Get-ChildItem $x -Recurse -Filter oggenc2.exe | Select-Object -First 1).FullName "$d\oggenc2.exe"
}
if (-not (Test-Path "$d\Magpie\Magpie.exe")) {
    $x = Get-Zip 'https://github.com/Blinue/Magpie/releases/download/v0.13.0/Magpie-v0.13.0-x64.zip' 'Magpie'
    Move-Item $x "$d\Magpie"
}
if (-not (Test-Path "$d\ogg-winmm\winmm.dll")) {
    & (Join-Path $d 'ogg-winmm\quellcode\build-winmm.ps1')
}

# ZIP mit einem Ordner „TuneLand-Patch“ darin
$stage = Join-Path $root 'build\stage\TuneLand-Patch'
if (Test-Path (Split-Path $stage)) { Remove-Item (Split-Path $stage) -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $root 'TuneLand installieren.cmd'), (Join-Path $root 'LIESMICH.txt'), (Join-Path $root 'LICENSE'), (Join-Path $root 'THIRD-PARTY.md') $stage
Copy-Item $d (Join-Path $stage 'dateien') -Recurse
Remove-Item (Join-Path $stage 'dateien\Magpie\config'), (Join-Path $stage 'dateien\Magpie\logs'), (Join-Path $stage 'dateien\Magpie\cache') -Recurse -Force -ErrorAction SilentlyContinue

$release = Join-Path $root 'release'
New-Item -ItemType Directory -Force $release | Out-Null
$zipOut = Join-Path $release "TuneLand-Patch-v$Version.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut }
# Einträge selbst anlegen: PowerShell 5.1 schreibt sonst Backslashes in die ZIP-Pfade
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$base = Split-Path $stage
$zip = [IO.Compression.ZipFile]::Open($zipOut, 'Create')
try {
    foreach ($file in Get-ChildItem $stage -Recurse -File) {
        $name = $file.FullName.Substring($base.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $name, 'Optimal')
    }
} finally { $zip.Dispose() }
Write-Host "Fertig: $zipOut"
