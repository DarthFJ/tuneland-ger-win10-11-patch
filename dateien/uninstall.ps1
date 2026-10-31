# Entfernt TuneLand samt Verknüpfungen und Eintrag in „Apps“
Add-Type -AssemblyName System.Windows.Forms
$root = $PSScriptRoot

$answer = [System.Windows.Forms.MessageBox]::Show(
    "TuneLand wirklich vollständig entfernen?`n`n$root", 'TuneLand deinstallieren', 'YesNo', 'Question')
if ($answer -ne 'Yes') { exit }

Set-Location $env:TEMP
Get-Process otvdm*, Magpie -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'TuneLand.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'TuneLand') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TuneLand' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $root) {
    [System.Windows.Forms.MessageBox]::Show("Einige Dateien waren noch in Benutzung. Bitte den Ordner später von Hand löschen:`n$root",
        'TuneLand deinstallieren', 'OK', 'Warning') | Out-Null
} else {
    [System.Windows.Forms.MessageBox]::Show('TuneLand wurde entfernt.', 'TuneLand deinstallieren', 'OK', 'Information') | Out-Null
}
