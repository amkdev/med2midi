# Projekt: med2midi – Mac-App für OctaMED-/MED-SoundStudio-Songs nach MIDI

## Ziel

Baue eine **macOS-App (Swift, SwiftUI)**, mit der ich meine alten Amiga-Songs aus
OctaMED / OctaMED SoundStudio ansehen, prüfen und verlustfrei nach Standard-MIDI
exportieren kann, damit ich sie im DAW neu instrumentieren kann.

Die App **spielt nichts ab**. Sie zeigt die Songs so an, dass ich sie Pattern für
Pattern mit dem Original (OctaMED im Emulator) vergleichen kann, und exportiert
MIDI, SysEx-Dumps und Klanginformationen.

**Wichtig:** Meine Songs verwenden ausschließlich MIDI-Instrumente, keine Samples.
Sample-Wiedergabe, Synth-Instrumente, Audio-Effekte und der Mixing-Modus sind
irrelevant. Diese Daten nur überspringen, nicht interpretieren.

Einige Songs enthalten zusätzlich **SysEx-Dumps**. Das sind Programmspeicher-Dumps
meines multitimbralen Yamaha-Soundmoduls **MU80** (XG, 32 Parts), also die
Klangeinstellungen, die ich für den Song programmiert habe. Sie werden entweder zu
Beginn des Songs gesendet oder sind nur in der MED-Datei gespeichert, ohne
automatisch ausgelöst zu werden. Diese Dumps sollen unbedingt erhalten bleiben.

## Referenzquellen (zuerst lesen)

1. **MMD_FileFormat.doc** von Teijo Kinnunen: offizielle Formatbeschreibung
   MMD0–MMD3. Zu finden u. a. in den UADE-Quellen unter
   `amigasrc/players/med/MMD_FileFormat.doc` (z. B. im GitHub-Repo `dv1/ion_player`
   unter `extern/uade-2.13/...`). Dort auch `proplayer.doc`.
   Hinweis: MMD3 ist strukturell identisch mit MMD2.
2. **OpenMPT `soundlib/Load_med.cpp`** (github.com/OpenMPT/openmpt): Referenz-
   Implementierung für knifflige Details (Tempo-Modi, MIDI-Presets inkl. altem
   Preset-Modus, Befehlsbedeutungen, Transponierung).
3. **Haskell-Bibliothek `med-module`** (Hackage): zweite unabhängige
   Implementierung, enthält u. a. Strukturen für MIDI-Befehle (`MMDMIDICmd3x`)
   und **Dumps** (`MMDDump`, `MMDDumpData`).
4. **Tutka** (github.com/findsp/tutka, Original von Vesa Halttunen, GPL): ein
   Tracker-MIDI-Sequencer, der OctaMED-SoundStudio-Songs (MMD2/MMD3) lädt,
   speichert und als MIDI exportiert. **Sehr wertvoll, weil rein MIDI-orientiert –
   genau mein Anwendungsfall.**
   - `src/mmd.h` / `src/mmd.cpp`: vollständige C-Strukturen und Parser für MMD2,
     inkl. `InstrExt` (hold, decay, suppress_midi_off, long_midi_preset),
     `MMDDump`/`MMDDumpData` (SysEx-Dumps mit Namen), `MMDMIDICmd3x`
     (frei belegbare Controller-Befehle 31–3F), Befehlsseiten, Blocknamen,
     Playsequences und Sections.
   - `src/conversion.cpp` (`mmd2ToSong`, `mmd2CommandToSongCommand`): die
     praktische **Bedeutung der MIDI-Befehle**, u. a.: 01–03/13 Pitchbend,
     04 Modulation (CC1), 08 Hold, 09 Ticks pro Zeile, 0A/0C Velocity
     (OctaMED-MIDI-Lautstärke 0–95 → 0–127), 0D Channel Pressure, 0E Pan (CC10),
     0F Tempo inkl. Sonderwerte F1–FF (Retrigger, Delay, Note stoppen, Song
     stoppen), **10 = SysEx-Dump senden**, 16 Volume (CC7), 1D Blockende,
     1F Delay/Retrigger, 31–3F Controller laut Cmd3x-Tabelle.
   - `songToSMF`: MIDI-Export durch Abspielen des Songs in einen Puffer – das
     Prinzip (Player-Simulation erzeugt Event-Liste) ist ein guter Ansatz für
     korrektes Timing.
   - **Bekannte Lücken in Tutka, die wir besser machen müssen:** MIDI-Preset
     (`midipreset`/`long_midi_preset`) wird beim Import nicht übernommen, Decay
     und suppress_midi_off werden ignoriert, Hold nur als Ja/Nein, Cmd3x nur für
     Standard-CC (nicht RPN/NRPN), Songtransponierung und Tempo-Modus-Flags
     (BPM/Zeilen pro Beat) werden nicht ausgewertet, mehrere Befehle
     (z. B. 05–07, 11, 12, 14, 15, 17–1C, 1E) sind nicht abgebildet, MIDI-Export
     nur als eine einzige Spur.
   - Lizenz GPL: Code als Referenz lesen; bei direkter Übernahme von Code die
     GPL beachten.
5. **MU80 Owner's Manual** (MIDI-Datenformat-Anhang mit Adresstabellen) und die
   **XG-Spezifikation** von Yamaha – für die Entschlüsselung der Dumps.

Bei Widersprüchen zwischen den Quellen: dokumentieren und mit meinen echten
Songdateien bzw. der Emulator-Referenz klären, nicht raten.

## Architektur

- **`MEDKit`** (Swift Package, ohne UI): Parser, Datenmodell, Player-Simulation
  (erzeugt eine zeitlich korrekte Event-Liste, spielt aber nichts ab),
  MIDI-Writer, SysEx-/MU80-Decoder, Vergleichslogik. Vollständig mit Unit-Tests
  gegen meine Beispieldateien abgedeckt.
- **App** (SwiftUI): nur Darstellung und Bedienung, nutzt `MEDKit`.
- Datenmodell: Song → Playsequences/Sections → Blöcke → Spuren → Zeilen
  (Note, Instrument, Befehle je Befehlsseite).
- MIDI-Dateien mit eigenem, kleinem SMF-Writer/-Reader (keine schweren
  Abhängigkeiten).
- Originaldateien werden nie verändert.
- Formatdetails im Code mit Quellenangabe kommentieren (Spezifikation bzw.
  Datei/Funktion im Referenz-Code).

## Funktionen der App

### 1. Songansicht
- Songs per Öffnen-Dialog oder Drag & Drop laden; mehrere Songs gleichzeitig
  (Seitenleiste mit Songliste).
- Allgemeine Infos: Formatversion (MMD0–3), Songname, Anzahl Songs in der Datei
  (Multi-Modul), Tempo-Einstellungen (Tempo-Modus/BPM, Ticks pro Zeile, Zeilen
  pro Beat), Songtransponierung.
- Playsequences und Sections als Liste; Klick springt zum Block.
- **Warnungen**: unbekannte oder nicht unterstützte Befehle, Instrumente, die
  sich einen MIDI-Kanal teilen, Auffälligkeiten beim Parsen. Unbekanntes nie
  stillschweigend ignorieren.
- Statistik aller verwendeten Befehle (Nummer, Häufigkeit, Fundstellen).

### 2. Pattern-Ansicht (Tracker-Stil)
- Block als Tabelle: Zeilen × Spuren mit Note, Instrument und Befehlen, inkl.
  zusätzlicher Befehlsseiten; Darstellung so nah wie möglich an OctaMED
  (Hex-Werte, Notennamen), Monospace-Schrift.
- Durchschalten **in Songreihenfolge** (Section → Playsequence → Block) sowie
  direkt nach Blocknummer; Tastaturkürzel für vor/zurück.
- Anzeige der aktuellen Position (Section, Sequenzposition, Block, Zeile) und der
  berechneten Zeit (Takt/Beat und Sekunden) – so kann ich im Emulator exakt die
  gleiche Stelle anfahren.
- Beim Überfahren eines Befehls mit der Maus: Erklärung, was er auf MIDI-Ebene
  bewirkt (z. B. „0C 40 → Velocity 85“).
- Optional: Spuren nach Instrument einfärben.

### 3. Instrumente & Klänge
- Tabelle aller Instrumente: Name, MIDI-Kanal, Preset/Programm (inkl.
  long_midi_preset), Transpose, Default-Lautstärke, Hold, Decay,
  suppress_midi_off.
- Verknüpfung mit den entschlüsselten MU80-Einstellungen (siehe unten):
  „Instrument X → MU80-Part Y → Voice Z mit diesen Einstellungen“.

### 4. SysEx-Dumps
- Liste aller in der Datei gespeicherten Dumps: Index, Name, Länge, Prüfung
  F0…F7, Herstellerkennung und Geräte-/Modell-ID (Yamaha = 0x43), Checksumme.
- Status pro Dump: *beim Songstart gesendet*, *während des Songs gesendet*
  (mit Position, Befehl 10) oder *nur gespeichert*. Wie OctaMED Dumps beim
  Songstart sendet, aus Spezifikation/Referenz-Code ermitteln.
- Hex-Ansicht eines Dumps.

#### MU80-Dumps entschlüsseln
Ziel: Ich will beim Neu-Instrumentieren sehen, welcher Part welchen Klang mit
welchen Einstellungen hatte.
- Dumps nach Typ erkennen: **XG-Bulk-Dumps / XG-Parameter-Changes**
  (Model-ID 0x4C: XG System, Effekte, Multi Part, Drum Setup) und
  **MU80-native Dumps** (Model-ID 0x49, z. B. System, Internal Performance).
- Lesbare **Klangtabelle** pro Part: MIDI-Kanal, Bank MSB/LSB, Programm und
  **Voice-Name** (aus der MU80/XG-Voiceliste), Volume, Pan,
  Reverb-/Chorus-/Variation-Send, Filter (Cutoff/Resonanz), Hüllkurve,
  Transpose/Tuning; dazu die Effekttypen und ggf. Drum-Setup-Änderungen.
- Programm-/Bankwechsel und Controller aus dem Songverlauf selbst einbeziehen
  (Anfangszustand pro Part).

### 5. Export
Pro Song ein Export-Ordner mit:
- **MIDI-Datei** (Standard MIDI File Typ 1):
  - **eine Spur pro MED-Instrument** (Standard), mit MIDI-Kanal und Programm des
    Instruments; Spurnamen aus den Instrumentnamen. Teilen sich mehrere
    Instrumente einen Kanal, trotzdem getrennte Spuren (Warnung anzeigen).
  - Alternativ wählbar: eine Spur pro MIDI-Kanal oder pro MED-Track.
  - Korrekte Tempo-Map inkl. Tempowechseln per Befehl.
  - Marker am Beginn jedes Blocks / jeder Section (Songstruktur im DAW sichtbar).
  - Programmwechsel am Anfang aus den Instrument-Presets.
  - Notenlängen korrekt: Hold/Decay, Note-Off-Befehle, nächste Note auf derselben
    Spur – kritischer Punkt, sorgfältig gegen Referenzen prüfen.
  - Velocity/CC7, Pitchbend, Controller (inkl. Cmd3x mit RPN/NRPN),
    Programmwechsel per Befehl, Transponierung (Song + Instrument),
    Delay/Retrigger.
  - Bei ausgelösten Dumps ein Marker `SysEx: <Name>`; per Option die Dumps
    zusätzlich als SysEx-Events einbetten (Songstart-Dumps vor Takt 1).
- **`.syx`-Datei pro Dump** (roher F0…F7-Stream), egal ob ausgelöst oder nicht.
- **Manifest** (JSON + lesbare Textversion): Dumps mit Status und Position,
  Klangtabelle, Instrumentliste, Warnungen.
- **Stapelexport** für viele Songs auf einmal, mit Übersicht (welche Songs
  sauber, welche mit Warnungen) und Erkennung identischer Dumps über einen Hash
  (welche Songs nutzen welchen Klangsatz).

### 6. Vergleich mit Emulator-Referenz
Ich nehme einzelne Songs per Emulator auf (OctaMED im Emulator, MIDI-Out wird im
DAW als MIDI-Datei mitgeschnitten).
- Referenz-MIDI zu einem Song laden und mit dem eigenen Export abgleichen
  (Tempo-/Offset-Ausrichtung am ersten Event).
- Abweichungen (fehlende/zusätzliche Noten, Tonhöhe, Velocity, Länge, Timing
  oberhalb einer Toleranz) als Liste **und direkt in der Pattern-Ansicht** an
  Block und Zeile markieren; Klick auf eine Abweichung springt dorthin.
- Zusammenfassung pro Spur.

Ziel: Export und Emulator-Referenz stimmen (bis auf Jitter) überein.

## Vorgehen in Phasen

1. **MEDKit-Parser + Songansicht + Pattern-Ansicht** (nur lesen/anzeigen,
   Warnungen, Befehlsstatistik). Damit analysieren wir zuerst meine echten
   Dateien und sehen, welche Features ich tatsächlich verwendet habe.
2. **Instrumente, SysEx-Dumps (Liste/Hex), MIDI-Export.**
3. **MU80-Entschlüsselung und Klangtabelle.**
4. **Vergleich mit Emulator-Referenz.**
5. **Stapelexport.**

Implementiert wird vorrangig, was in meinen Songs wirklich vorkommt.

## Arbeitsweise

- Vor jeder Phase einen kurzen Plan vorlegen und **meine Bestätigung abwarten**,
  bevor Dateien angelegt oder größere Änderungen umgesetzt werden.
- Nach jeder Phase: Tests laufen lassen, kurz zusammenfassen, was funktioniert und
  was offen ist.

## Start

Lies zuerst die Referenzquellen, schlage mir dann Projektstruktur und Plan für
Phase 1 vor. Die Beispieldateien liegen im Ordner `songs/`.
