# TuneLand GER Win10/11 Patch

Damit läuft **„TuneLand mit Ron Williams“** (7th Level, 1994, deutsche Version) auf modernem Windows.
Ein Doppelklick genügt. Danach läuft das Spiel **mit Musik** und **im Vollbild**.
Wie im Original läuft TuneLand dabei **von der CD**: Zum Spielen muss die CD eingelegt oder das Abbild gemountet sein.

> *English summary below.*

## Was man braucht

- Windows 10 oder 11 (64 Bit)
- Die **deutsche TuneLand-CD** oder ein Abbild davon als **BIN/CUE** (Volume-Name `GERMTUNE`)
- Für Abbilder ein Programm zum Mounten, z. B. [WinCDEmu](https://wincdemu.sysprogs.org/)

## Unterstützte Versionen

Getestet ist der Patch **nur mit der deutschen Version** („TuneLand mit Ron Williams“, CD-Name `GERMTUNE`,
Programm `TUNELAND\TUNEGERM.EXE`).

Andere Sprachfassungen, etwa das englische Original *Howie Mandel's TuneLand*, werden **derzeit nicht erkannt**.
Der Installer sucht fest nach `TUNEGERM.EXE` und `JUKEGERM.EXE`, und andere Fassungen heißen sehr wahrscheinlich anders.
Grundsätzlich dürfte der Ansatz dort genauso funktionieren, denn es ist dieselbe Engine mit CD-Musik.
Wer eine andere Version besitzt und helfen möchte, kann gern ein [Issue](../../issues) mit der Dateiliste der CD
(Ordner `TUNELAND`) und dem CD-Namen anlegen.

## Installation

1. [Release-ZIP herunterladen](../../releases/latest) und entpacken.
2. CD einlegen **oder** die `.cue`-Datei mounten (WinCDEmu: Rechtsklick › *Einhängen*).
3. **`TuneLand installieren.cmd`** doppelklicken › **Installieren**.
4. Fertig: TuneLand startet über das Desktop-Symbol. Die CD bzw. das gemountete Abbild muss dabei eingelegt sein.

Installiert wird nach `%LOCALAPPDATA%\Programs\TuneLand`. Dafür sind keine Administratorrechte nötig.
Entfernen geht über *Startmenü › TuneLand › TuneLand deinstallieren* oder *Einstellungen › Apps*.

> Windows SmartScreen kann beim ersten Start warnen, weil die Datei aus dem Internet stammt:
> *Weitere Informationen › Trotzdem ausführen*.

## Im Spiel

| Taste | Wirkung |
|---|---|
| F1 / F2 | Hilfe von Ron Williams |
| Esc | zurück auf den Hof |
| Shift + Esc | TuneLand sofort beenden |
| Alt + Shift + A | Vollbild an/aus (falls es nicht automatisch kommt) |

Beim **ersten** Start dauert es ein paar Sekunden bis zum Vollbild, weil der Patch zuerst die Bildfläche
vermessen muss. Ab dann geht es sofort.

## Was der Patch macht

TuneLand ist ein 16-Bit-Programm für Windows 3.1 und hat drei Probleme auf heutigen Rechnern:

| Problem | Lösung |
|---|---|
| 64-Bit-Windows führt keine 16-Bit-Programme aus | [otvdm/winevdm](https://github.com/otya128/winevdm) als private Kopie im Installationsordner |
| Die Lieder sind Audiotracks auf der CD. Gemountete Abbilder zeigen sie nicht, und otvdm reicht die CD-Befehle nicht passend weiter | Der Installer liest die 97 Lieder von der CD oder direkt aus der BIN und wandelt sie in OGG um. Eine angepasste [ogg-winmm](https://github.com/ayuanx/ogg-winmm)-DLL spielt sie ab, wenn das Spiel „CD-Track X“ verlangt |
| Das Spiel zeigt ein kleines 640×480-Bild mitten auf einem schwarzen Bildschirm | [Magpie](https://github.com/Blinue/Magpie) schneidet die Bildfläche aus und skaliert sie im 4:3-Format auf Vollbild. Der Ausschnitt wird automatisch erkannt |

Im Einzelnen:

1. Der Installer sucht die CD auf allen Laufwerken.
2. Die Musik kommt von einer echten CD per Raw-Read. Bei einem gemounteten Abbild sucht der Installer die passende
   `.cue` selbst: neben dem Patch-Ordner, auf dem Desktop, in *Dokumente* und in *Downloads*. Dabei prüft er den Volume-Namen
   im Abbild. Findet er keine, fragt er nach.
3. Das Spiel selbst wird **nicht** auf die Festplatte kopiert. Der Starter sucht bei jedem Start die CD und startet
   TuneLand direkt von dort. Fehlt sie, bittet er darum. Die `7thlevel.ini`, die früher das Original-Setup angelegt hat,
   schreibt er jeweils passend zum CD-Laufwerk.
4. Er legt Verknüpfungen auf dem Desktop und im Startmenü an, auch für den *Tunes-Player*, und einen Eintrag unter *Apps*.

Der Patch enthält **keine Spielinhalte**. Nur die Lieder werden bei der Installation von der eigenen CD in OGG
umgewandelt, denn die CD-Audiotracks lassen sich unter otvdm und von gemounteten Abbildern nicht direkt abspielen.

## Fehlerhilfe

- **„Keine TuneLand-CD gefunden“** (Installer) bzw. **„Bitte legen Sie die TuneLand-CD ein“** (beim Spielstart):
  Die CD bzw. das Abbild ist nicht eingelegt oder gemountet. Einlegen bzw. mounten, dann *Wiederholen*.
- **Frage nach der CUE-Datei**: Die `.cue` zum gemounteten Abbild auswählen. Sie muss neben der `.bin` liegen.
- **Kein Vollbild**: Alt + Shift + A drücken. Nach einem Wechsel von Bildschirm oder Auflösung erkennt der Patch die
  Bildfläche neu. Andernfalls hilft es, `bildausschnitt.txt` im Installationsordner zu löschen.
- **Keine Musik**: Unter `%LOCALAPPDATA%\Programs\TuneLand\otvdm\` sollte ein Ordner `Music` mit `Track02.ogg` bis
  `Track98.ogg` liegen. `winmm.log` daneben zeigt, welche CD-Befehle das Spiel geschickt hat.

## Für Entwickler

```
TuneLand installieren.cmd      Einstieg (startet dateien\install.ps1)
dateien\install.ps1            Installer mit Oberfläche (WinForms)
dateien\launcher.ps1           Starter: otvdm + automatisches Vollbild (wird zu TuneLand.ps1)
dateien\uninstall.ps1          Deinstallation
dateien\TuneLandHelper.cs      CUE/BIN- und CD-Zugriff, OGG-Umwandlung, Bildflächen-Erkennung
dateien\magpie-config.json     Vorlage für das Magpie-Profil
dateien\ogg-winmm\quellcode\   geänderter ogg-winmm-Quellcode, Diff und Build-Skript
tools\build-release.ps1        lädt die Fremdprogramme und baut das Release-ZIP
```

Die Fremdprogramme (otvdm, Magpie, oggenc2, `winmm.dll`) liegen nicht im Repository. `tools\build-release.ps1` lädt
sie bzw. baut sie und erstellt `release\TuneLand-Patch-v<Version>.zip`. Details und Lizenzen: [THIRD-PARTY.md](THIRD-PARTY.md).

## Lizenz

Die Skripte dieses Projekts stehen unter der **GPL-2.0-or-later** (siehe [LICENSE](LICENSE)).
Für die enthaltenen Fremdprogramme gelten deren eigene Lizenzen ([THIRD-PARTY.md](THIRD-PARTY.md)).
TuneLand ist ein Produkt von 7th Level, Inc. Dieses Projekt ist inoffiziell und steht in keiner Verbindung dazu.

---

## English summary

One-click patch that makes the **German** release of *TuneLand* (7th Level, 1994) run on Windows 10/11:
CD music restored and automatic fullscreen. The game still runs from the CD, so the disc must be inserted
(or the image mounted) to play.

1. Download the release ZIP and extract it.
2. Insert the CD or mount the BIN/CUE image.
3. Double-click `TuneLand installieren.cmd` and click **Installieren**.

How it works: it uses a private copy of [otvdm](https://github.com/otya128/winevdm) to run the 16-bit game. The CD audio
tracks are read from the disc or the BIN and encoded to OGG. A patched [ogg-winmm](https://github.com/ayuanx/ogg-winmm)
plays them; the patch adds handling for `mciSendCommandW`/`mciSendStringW`, which otvdm uses. A portable
[Magpie](https://github.com/Blinue/Magpie) crops and upscales the centred 640×480 picture. No game content is
included. Scripts are GPL-2.0-or-later; bundled tools keep their own licenses.

**Supported versions:** only tested with the **German** release (disc label `GERMTUNE`, `TUNELAND\TUNEGERM.EXE`).
Other language versions, such as the English *Howie Mandel's TuneLand*, are not detected yet, because the installer looks
for the German file names. If you own another version, please open an [issue](../../issues) with the file list of
the `TUNELAND` folder and the disc label.
