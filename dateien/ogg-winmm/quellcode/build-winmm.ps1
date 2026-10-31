# Baut die angepasste winmm.dll (ogg-winmm mit Unicode-MCI-Unterstützung für otvdm)
# Lädt dazu ogg-winmm (für die mitgelieferten Ogg/Vorbis-Bibliotheken) und den Compiler w64devkit (32 Bit)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'

$here     = $PSScriptRoot
$work     = Join-Path $here '..\..\..\build\winmm'
$upstream = '11c13ecf727fc0b00b46e04acbf503a60e7df1db'   # ayuanx/ogg-winmm, Stand v2025.01.16
$devkit   = 'https://github.com/skeeto/w64devkit/releases/download/v2.11.0/w64devkit-x86-2.11.0.7z.exe'

New-Item -ItemType Directory -Force $work | Out-Null
$work = (Resolve-Path $work).Path

if (-not (Test-Path "$work\ogg-winmm-$upstream")) {
    Invoke-WebRequest "https://github.com/ayuanx/ogg-winmm/archive/$upstream.zip" -OutFile "$work\ogg-winmm.zip"
    Expand-Archive "$work\ogg-winmm.zip" $work -Force
}
if (-not (Test-Path "$work\w64devkit\bin\gcc.exe")) {
    Invoke-WebRequest $devkit -OutFile "$work\w64devkit.7z.exe"
    & "$work\w64devkit.7z.exe" "-o$work" -y | Out-Null
}

# Geänderte Quellen über das Original legen
$src = "$work\ogg-winmm-$upstream"
Copy-Item "$here\ogg-winmm.c", "$here\stubs.c", "$here\stub.h" $src -Force

$env:PATH = "$work\w64devkit\bin;$env:PATH"
Push-Location $src
try {
    gcc -m32 -std=gnu99 -static-libgcc '-Wl,--enable-stdcall-fixup,--gc-sections' -s -O2 -shared -o winmm.dll `
        ogg-winmm.c player.c stubs.c ogg-winmm.def -Ilibs/include -Llibs -lwinmm '-l:libvorbisfile.a' '-l:libvorbis.a' '-l:libogg.a'
    if ($LASTEXITCODE -ne 0) { throw "gcc ist fehlgeschlagen ($LASTEXITCODE)" }
} finally { Pop-Location }

Copy-Item "$src\winmm.dll" (Join-Path $here '..\winmm.dll') -Force
Write-Host 'Fertig: dateien\ogg-winmm\winmm.dll'
