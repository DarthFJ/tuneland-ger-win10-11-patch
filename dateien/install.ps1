# TuneLand-Patch: richtet TuneLand von CD oder gemountetem BIN/CUE als Desktop-Anwendung ein
param(
    [string]$Ziel = (Join-Path $env:LOCALAPPDATA 'Programs\TuneLand'),
    [switch]$OhneMusik,    # nur für Tests: Musikumwandlung überspringen
    [switch]$OhneVerknuepfungen,
    [switch]$Automatisch,   # ohne Fenster (für Tests)
    [string]$Vorschau,      # nur für Tests: Fenster als PNG speichern und beenden
    [switch]$Reparieren     # nur Symbole, Verknüpfungen und Apps-Eintrag neu anlegen
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Path (Join-Path $here 'TuneLandHelper.cs') -ReferencedAssemblies System.Drawing
Add-Type -Name Dpi -Namespace Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[Native.Dpi]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Oberfläche ----------
# Schriften in Punkt wachsen mit der Bildschirmskalierung von selbst mit, Pixelmaße rechnen wir selbst um
$g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$scale = $g.DpiX / 96.0
$g.Dispose()
function Px([int]$v) { [int][math]::Round($v * $scale) }
function Place($control, [int]$x, [int]$y, [int]$w, [int]$h) { $control.SetBounds((Px $x), (Px $y), (Px $w), (Px $h)) }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'TuneLand GER Win10/11 Patch'
$form.AutoScaleMode = 'None'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.ClientSize = New-Object System.Drawing.Size((Px 580), (Px 320))
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'

$title = New-Object System.Windows.Forms.Label
$title.Text = 'TuneLand für Windows 10/11 einrichten'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
Place $title 20 16 540 34

$intro = New-Object System.Windows.Forms.Label
$intro.Text = "Legen Sie die TuneLand-CD ein oder mounten Sie das BIN/CUE-Abbild. " +
              "Der Patch richtet otvdm, die Musik und den Start im Vollbild ein. " +
              "Das Spiel läuft weiterhin von der CD – sie muss zum Spielen eingelegt sein."
Place $intro 20 60 540 84

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Bereit.'
Place $status 20 156 540 48

$bar = New-Object System.Windows.Forms.ProgressBar
Place $bar 20 212 540 22

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Installieren'
Place $btnStart 300 262 130 38

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Schließen'
Place $btnClose 440 262 120 38
$btnClose.Add_Click({ $form.Close() })

$form.Controls.AddRange(@($title, $intro, $status, $bar, $btnStart, $btnClose))
$form.AcceptButton = $btnStart

function Set-Status([string]$text, [int]$percent = -1) {
    $status.Text = $text
    if ($percent -ge 0) { $bar.Value = [math]::Min(100, $percent) }
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------- Quelle finden ----------
function Find-GameDrive {
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady -and (Test-Path (Join-Path $d.RootDirectory.FullName 'TUNELAND\TUNEGERM.EXE'))) { return $d }
    }
    return $null
}

function Find-CueFor([string]$label) {
    $dirs = @((Split-Path $here), (Split-Path (Split-Path $here)),
              [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
              (Join-Path $env:USERPROFILE 'Downloads')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    foreach ($dir in $dirs) {
        foreach ($cue in Get-ChildItem $dir -Filter *.cue -Recurse -Depth 3 -ErrorAction SilentlyContinue) {
            if (Test-CueFor $cue.FullName $label) { return $cue.FullName }
        }
    }
    return $null
}

function Test-CueFor([string]$cue, [string]$label) {
    try {
        $data = $null
        $tracks = [TuneLand.Cue]::ParseAudio($cue, [ref]$data)
        return $tracks.Count -gt 0 -and $data -and (Test-Path $data) -and ([TuneLand.Cue]::ReadVolumeLabel($data) -eq $label)
    } catch { return $false }
}

# Liefert @{ Source; Tracks; Beschreibung } – echte CD bevorzugt, sonst die passende CUE
function Get-AudioSource($drive) {
    try {
        $cd = New-Object TuneLand.CdSource($drive.Name[0])
        $tracks = $cd.ReadAudioTracks()
        if ($tracks.Count -gt 0) { return @{ Source = $cd; Tracks = $tracks; Beschreibung = "CD in Laufwerk $($drive.Name)" } }
        $cd.Dispose()
    } catch {}

    # Gemountete Abbilder (z. B. WinCDEmu) zeigen keine Audiotracks – dann die CUE-Datei lesen
    $label = $drive.VolumeLabel
    $cue = Find-CueFor $label
    if (-not $cue) {
        [System.Windows.Forms.MessageBox]::Show(
            "Das Laufwerk $($drive.Name) liefert keine Musiktracks (bei gemounteten Abbildern normal).`n`n" +
            "Bitte wählen Sie im nächsten Fenster die passende .cue-Datei aus.",
            'TuneLand-Patch', 'OK', 'Information') | Out-Null
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'CUE-Datei (*.cue)|*.cue'
        $dlg.Title = 'TuneLand-Abbild auswählen (.cue)'
        if ($dlg.ShowDialog($form) -ne 'OK') { throw 'Keine CUE-Datei ausgewählt – ohne sie fehlt die Musik.' }
        if (-not (Test-CueFor $dlg.FileName $label)) { throw 'Diese CUE-Datei gehört nicht zur eingelegten TuneLand-CD.' }
        $cue = $dlg.FileName
    }
    $data = $null
    $tracks = [TuneLand.Cue]::ParseAudio($cue, [ref]$data)
    return @{ Source = (New-Object TuneLand.BinSource); Tracks = $tracks; Beschreibung = (Split-Path $cue -Leaf) }
}

# ---------- Hilfen ----------
function New-Shortcut([string]$path, [string]$arguments, [string]$icon, [string]$desc) {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($path)
    $lnk.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lnk.Arguments = $arguments
    $lnk.WorkingDirectory = $Ziel
    $lnk.WindowStyle = 7
    if ($icon -and (Test-Path $icon)) { $lnk.IconLocation = $icon }
    $lnk.Description = $desc
    $lnk.Save()
}

function Save-Icon([string]$exe, [string]$ico) {
    try { if ([TuneLand.NeIcon]::Save($exe, $ico)) { return } } catch {}
    try {
        $i = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
        $fs = [IO.File]::Create($ico); $i.Save($fs); $fs.Close()
    } catch {}
}

function Stop-Installed {
    Get-Process otvdm*, Magpie -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($Ziel, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

# ---------- Installation ----------
function Install-TuneLand {
    Set-Status 'Suche TuneLand-CD …' 2
    $drive = Find-GameDrive
    if (-not $drive) { throw 'Keine TuneLand-CD gefunden. Bitte CD einlegen oder BIN/CUE mounten und erneut auf „Installieren“ klicken.' }

    Set-Status "TuneLand gefunden auf $($drive.Name) – prüfe Musiktracks …" 4
    $audio = Get-AudioSource $drive
    if ($audio.Tracks.Count -eq 0) { throw 'Auf der Quelle wurden keine Musiktracks gefunden.' }

    Set-Status 'Bereite Zielordner vor …' 6
    Stop-Installed
    if (Test-Path $Ziel) { Remove-Item $Ziel -Recurse -Force }
    New-Item -ItemType Directory -Force $Ziel | Out-Null

    # Laufzeit: otvdm mit eigener winmm.dll, Magpie, Starter
    Set-Status 'Kopiere Programmdateien …' 8
    Copy-Item (Join-Path $here 'otvdm') (Join-Path $Ziel 'otvdm') -Recurse
    Copy-Item (Join-Path $here 'ogg-winmm\winmm.dll') (Join-Path $Ziel 'otvdm\winmm.dll')
    Set-Content (Join-Path $Ziel 'otvdm\winmm.ini') -Encoding ascii -Value @(
        '[OGG-WinMM]', 'CDDAPath = Music', 'CDDAVolume = 100', 'MIDIVolume = 100', 'WAVEVolume = 100')
    Set-Status 'Kopiere Vollbild-Werkzeug (Magpie) …' 12
    Copy-Item (Join-Path $here 'Magpie') (Join-Path $Ziel 'Magpie') -Recurse
    Copy-Item (Join-Path $here 'TuneLandHelper.cs'), (Join-Path $here 'magpie-config.json'), (Join-Path $here 'uninstall.ps1') $Ziel
    Copy-Item (Join-Path $here 'launcher.ps1') (Join-Path $Ziel 'TuneLand.ps1')

    # Das Spiel selbst bleibt auf der CD; wie das Original-Setup nur den CD-Treiber in den Windows-Ordner von otvdm legen
    # (7thlevel.ini schreibt der Starter bei jedem Start passend zum aktuellen CD-Laufwerk)
    $src = Join-Path $drive.RootDirectory.FullName 'TUNELAND'
    Copy-Item (Join-Path $src 'MCICDA.DRV') (Join-Path $Ziel 'otvdm\WINDOWS\SYSTEM\mcicda.drv') -ErrorAction SilentlyContinue

    # Musik
    if (-not $OhneMusik) {
        $music = Join-Path $Ziel 'otvdm\Music'
        [TuneLand.Encoder]::Start((Join-Path $here 'oggenc2.exe'), $audio.Source, $audio.Tracks, $music)
        while (-not [TuneLand.Encoder]::Finished) {
            $done = [TuneLand.Encoder]::Done; $total = [TuneLand.Encoder]::Total
            Set-Status "Übernehme die Musik aus $($audio.Beschreibung): Lied $done von $total …" (40 + [int](50 * $done / $total))
            Start-Sleep -Milliseconds 150
        }
        if ([TuneLand.Encoder]::Error) { throw "Fehler bei der Musik: $([TuneLand.Encoder]::Error)" }
    }
    if ($audio.Source -is [IDisposable]) { $audio.Source.Dispose() }

    Set-Status 'Lege Verknüpfungen an …' 94
    Register-TuneLand $src

    Set-Status 'Fertig! TuneLand startet über das Symbol auf dem Desktop. Die CD bzw. das Abbild muss dabei eingelegt sein.' 100
}

# Symbole, Verknüpfungen und Eintrag in „Apps“ (auch einzeln aufrufbar, um eine Installation zu reparieren)
function Register-TuneLand([string]$src) {
    # Eigene Dateinamen pro Symbol: Windows merkt sich Symbole nach Pfad, ein gleichnamiges altes Bild bliebe sonst stehen
    Remove-Item (Join-Path $Ziel 'tuneland.ico'), (Join-Path $Ziel 'liederspieler.ico') -ErrorAction SilentlyContinue
    $icon = Join-Path $Ziel 'TuneLand-Spiel.ico'
    $iconSongs = Join-Path $Ziel 'TuneLand-Lieder.ico'
    Save-Icon (Join-Path $src 'TUNEGERM.EXE') $icon
    Save-Icon (Join-Path $src 'JUKEGERM.EXE') $iconSongs

    if ($OhneVerknuepfungen) { return }

    $run = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $Ziel 'TuneLand.ps1') + '"'
    New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'TuneLand.lnk') $run $icon 'TuneLand starten'
    $menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'TuneLand'
    New-Item -ItemType Directory -Force $menu | Out-Null
    New-Shortcut (Join-Path $menu 'TuneLand.lnk') $run $icon 'TuneLand starten'
    New-Shortcut (Join-Path $menu 'TuneLand Liederspieler.lnk') ($run + ' -Liederspieler') $iconSongs 'Die Lieder aus TuneLand abspielen'
    New-Shortcut (Join-Path $menu 'TuneLand deinstallieren.lnk') ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $Ziel 'uninstall.ps1') + '"') $null 'TuneLand entfernen'

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TuneLand'
    New-Item $key -Force | Out-Null
    $size = [int]((Get-ChildItem $Ziel -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
    $props = @{
        DisplayName     = 'TuneLand (7th Level, Patch für Windows 10/11)'
        DisplayIcon     = $icon
        Publisher       = '7th Level / TuneLand-Patch'
        InstallLocation = $Ziel
        UninstallString = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $Ziel 'uninstall.ps1') + '"'
    }
    foreach ($p in $props.GetEnumerator()) { Set-ItemProperty $key $p.Key $p.Value }
    Set-ItemProperty $key EstimatedSize $size -Type DWord
    Set-ItemProperty $key NoModify 1 -Type DWord
    Set-ItemProperty $key NoRepair 1 -Type DWord
    if (-not (Get-ItemProperty $key -ErrorAction SilentlyContinue).DisplayName) {
        throw 'Der Eintrag unter „Apps“ konnte nicht angelegt werden.'
    }

    # Explorer auffordern, Symbole neu zu laden
    [TuneLand.Shell]::Refresh()
}

if ($Vorschau) {
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save($Vorschau)
    $form.Close()
    return
}

if ($Reparieren) {
    $drive = Find-GameDrive
    if (-not $drive) { throw 'Keine TuneLand-CD gefunden.' }
    Register-TuneLand (Join-Path $drive.RootDirectory.FullName 'TUNELAND')
    Write-Host 'Symbole, Verknüpfungen und Apps-Eintrag neu angelegt.'
    return
}

if ($Automatisch) {
    Install-TuneLand
    Write-Host $status.Text
    return
}

$script:installiert = $false
$btnStart.Add_Click({
    if ($script:installiert) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Ziel 'TuneLand.ps1') + '"')
        $form.Close()
        return
    }
    $btnStart.Enabled = $false
    $btnClose.Enabled = $false
    try {
        Install-TuneLand
        $script:installiert = $true
        $btnStart.Text = 'Jetzt spielen'
        $btnStart.Enabled = $true
    } catch {
        Set-Status "Abgebrochen: $($_.Exception.Message)" 0
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'TuneLand-Patch', 'OK', 'Warning') | Out-Null
        $btnStart.Enabled = $true
    } finally {
        $btnClose.Enabled = $true
    }
})

[void]$form.ShowDialog()
