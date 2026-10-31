# Fremdkomponenten

Das Release-ZIP enthält folgende Programme anderer Projekte. Sie werden unverändert weitergegeben,
mit Ausnahme von ogg-winmm (siehe unten). Lizenztexte und Quellcode gibt es unter den Links.

| Komponente | Version | Lizenz | Zweck im Patch | Quelle |
|---|---|---|---|---|
| otvdm / winevdm | 0.9.0 | GPL-2.0 | führt 16-Bit-Windows-Programme unter 64-Bit-Windows aus | https://github.com/otya128/winevdm |
| ogg-winmm (angepasst) | Stand v2025.01.16 + Patch | GPL-2.0 | ersetzt die CD-Audio-Wiedergabe durch OGG-Dateien | https://github.com/ayuanx/ogg-winmm |
| oggenc2 (libVorbis 1.3.7) | 2.88 | GPL-2.0 (vorbis-tools), BSD (libvorbis/libogg) | wandelt die CD-Musik bei der Installation in OGG um | https://www.rarewares.org/ogg-oggenc.php |
| Magpie | 0.13.0 | GPL-3.0 | skaliert das Spielbild auf Vollbild | https://github.com/Blinue/Magpie |

## Änderung an ogg-winmm

otvdm übergibt die CD-Befehle des Spiels über die Unicode-Funktionen `mciSendCommandW` und
`mciSendStringW`. Das Original-ogg-winmm reicht diese unverändert an Windows weiter, deshalb blieb
die Musik stumm. Die Änderung fängt diese Befehle ab, wenn sie an `cdaudio` gehen, und behandelt sie
wie die ANSI-Varianten. Außerdem schreibt die DLL ein Protokoll (`winmm.log`) neben sich und kennt eine
optionale Einstellung `FirstTrackPosition`.

- Vollständiger geänderter Quellcode: `dateien/ogg-winmm/quellcode/`
- Nur die Änderungen als Diff: `dateien/ogg-winmm/quellcode/otvdm-unicode-mci.patch`
- Selbst bauen: `dateien/ogg-winmm/quellcode/build-winmm.ps1` (lädt Original-ogg-winmm und den Compiler w64devkit)

## Spielinhalte

Der Patch enthält **keine** Dateien, Bilder oder Musik von TuneLand. Das Spiel läuft immer von der
CD bzw. dem gemounteten Abbild des Benutzers. Nur die Lieder wandelt der Installer von dieser CD in
OGG-Dateien um, weil sich die CD-Audiotracks anders nicht abspielen lassen.
TuneLand ist ein Produkt von 7th Level, Inc.; dieses Projekt steht in keiner Verbindung dazu.
