@echo off
rem Startet den TuneLand-Patch (Doppelklick genügt)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0dateien\install.ps1"
