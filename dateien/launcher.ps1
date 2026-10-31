# TuneLand-Starter: startet das Spiel über otvdm und schaltet es mit Magpie automatisch auf Vollbild
param([switch]$Liederspieler)

$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$otvdm  = Join-Path $root 'otvdm\otvdmw.exe'
$game   = Join-Path $root 'Spiel'
$magpie = Join-Path $root 'Magpie\Magpie.exe'
$cache  = Join-Path $root 'bildausschnitt.txt'

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -Path (Join-Path $root 'TuneLandHelper.cs') -ReferencedAssemblies System.Drawing

$exe = if ($Liederspieler) { 'JUKEGERM.EXE' } else { 'TUNEGERM.EXE' }
$proc = Start-Process $otvdm -ArgumentList ('"' + (Join-Path $game $exe) + '"') -WorkingDirectory $game -PassThru

# Der Liederspieler ist ein normales kleines Fenster und braucht kein Vollbild
if ($Liederspieler) { exit }

# Auf das Spielfenster warten
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 120 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $i++) {
    Start-Sleep -Milliseconds 250
    $hwnd = [TuneLand.GameWindow]::Find($proc.Id)
}
if ($hwnd -eq [IntPtr]::Zero) { exit }

$scale = [TuneLand.GameWindow]::PhysicalScale()
$screen = [System.Windows.Forms.SystemInformation]::PrimaryMonitorSize
$key = '{0}x{1}@{2}' -f $screen.Width, $screen.Height, $scale

# Bildausschnitt aus dem Zwischenspeicher oder neu erkennen (bis zu 60 s, zwei gleiche Treffer in Folge)
$pic = $null
try {
    $saved = Get-Content $cache -ErrorAction Stop
    if ($saved[0] -eq $key) { $pic = $saved[1] -split ',' | ForEach-Object { [int]$_ } }
} catch {}
if (-not $pic) {
    $last = $null
    for ($i = 0; $i -lt 120 -and -not $proc.HasExited; $i++) {
        Start-Sleep -Milliseconds 500
        $now = [TuneLand.GameWindow]::DetectPicture($hwnd)
        if ($now -and $last -and (($now -join ',') -eq ($last -join ','))) { $pic = $now; break }
        $last = $now
    }
    if ($pic) { Set-Content $cache -Value @($key, ($pic -join ',')) -Encoding ascii }
}

$magpieProc = $null
if ($pic -and ($pic[0] + $pic[1]) -gt 0 -and -not (Get-Process Magpie -ErrorAction SilentlyContinue)) {
    # Magpie-Profil passend zu diesem Fenster und Bildschirm schreiben (Werte in echten Bildschirmpixeln)
    $tpl = [IO.File]::ReadAllText((Join-Path $root 'magpie-config.json'))
    $cfg = $tpl.Replace('__PATH__', $otvdm.Replace('\', '\\'))
    $cfg = $cfg.Replace('__CLASS__', [TuneLand.GameWindow]::ClassName($hwnd))
    $cfg = $cfg.Replace('__LEFT__',   [string][math]::Round($pic[0] * $scale))
    $cfg = $cfg.Replace('__TOP__',    [string][math]::Round($pic[1] * $scale))
    $cfg = $cfg.Replace('__RIGHT__',  [string][math]::Round($pic[2] * $scale))
    $cfg = $cfg.Replace('__BOTTOM__', [string][math]::Round($pic[3] * $scale))
    $cfgDir = Join-Path $root 'Magpie\config'
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $cfgDir 'config.json'), $cfg, (New-Object Text.UTF8Encoding $false))

    $magpieProc = Start-Process $magpie -ArgumentList '-t' -WorkingDirectory (Split-Path $magpie) -PassThru
}

$proc.WaitForExit()
if ($magpieProc -and -not $magpieProc.HasExited) { $magpieProc | Stop-Process -ErrorAction SilentlyContinue }
