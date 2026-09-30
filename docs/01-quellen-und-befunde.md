# Quellen, Widersprüche und Messungen an den echten Dateien

Stand: 2026-09-29. Alle Aussagen hier sind am Material belegt, nicht aus
Gedächtnis oder Analogie. Quellenangaben als Datei:Zeile.

## 1. Die Formatabstammung

Teijo Kinnunen, `MMD_FileFormat.doc` Revision 6 (01.02.1996), Zeilen 18–24 —
die Spezifikation des Formatautors, zu finden in den UADE-Amiga-Quellen:

> „The limitations in MMD0 block format forced me to create a new file format
> for OctaMED Professional, this format is 'MMD1'. […] 'MMD3' is identical to
> 'MMD2', but programs supporting this format must be able to recognize mixing
> mode of OctaMED Soundstudio."

| Version | Kennung | Herkunft |
|---|---|---|
| MMD0 | `0x4D4D4430` | MED V2.1 |
| MMD1 | `0x4D4D4431` | **OctaMED Professional** (daher die `.omp`-Dateinamen) |
| MMD2 | `0x4D4D4432` | OctaMED V5+ (Sections, Playseqs, bis 64 Spuren) |
| MMD3 | `0x4D4D4433` | OctaMED SoundStudio — Aufbau identisch zu MMD2 |

## 2. Widersprüche zwischen den Referenzen

### 2.1 Tutka liest MMD3 nicht und MMD0/MMD1 falsch

`tutka/src/mmd.cpp:170` (`MMD2_parse`):

```c
if (data[0]==0x4d && data[1]==0x4d && data[2]==0x44 && data[3] >= 0x30 && data[3] <= 0x32)
```

- **MMD3 (`0x33`) wird abgewiesen.** `ID_MMD3` kommt in `src/` nur als
  Header-Definition vor, nie in einer Verzweigung.
- **MMD0/MMD1 werden angenommen, aber mit MMD2-Layout gelesen.** `mmd.cpp:652`
  ruft unbedingt `MMD1Block_parse` auf; ein `MMD0Block_parse` existiert nicht.
  Der Songkopf wird immer als `MMD2song` gelesen.

Der Projekt-Prompt behauptet, Tutka lade MMD2/MMD3. Das trifft nicht zu.

**Folge:** Tutka ist als *Parser*-Referenz unbrauchbar, als *MIDI-Semantik*-
Referenz dagegen die beste verfügbare.

### 2.2 Befehle bedeuten für MIDI etwas anderes als für Samples

Beispiel `0x16`:

| Quelle | Deutung |
|---|---|
| OpenMPT `Load_med.cpp:555` | `// 0x16: Loop` → `CMD_MODCMDEX 0x60` |
| Tutka `conversion.cpp:165` | `commandconversion[22] = CommandMidiControllers + 7` → **CC7 Volume** |

Kein Fehler einer Seite: OpenMPT implementiert die Sample-Bedeutung, Tutka die
MIDI-Bedeutung. **Für dieses Projekt gilt durchgehend die MIDI-Deutung.**

Achtung beim Lesen von Tutkas Tabelle: sie ist **dezimal** indiziert.
`commandconversion[22]` ist Befehl `0x16`, nicht `0x22`.

### 2.3 Arbeitsteilung der Quellen

| Frage | Leitquelle |
|---|---|
| Dateistruktur, Versionsunterschiede | Kinnunen-Spezifikation, dann OpenMPT |
| Bedeutung der Befehle auf MIDI-Ebene | Tutka `conversion.cpp` |
| Letzte Instanz bei Timing/Dumps | UADE `amigasrc/players/med/` (68k-Assembler) |

## 3. Messung: fünf echte Dateien aus `songs/`

Gemessen mit einem Parser nach Spezifikation. `modlen` stimmt bei allen fünf
exakt mit der Dateigröße überein — der Leser kann sich daran selbst prüfen.

| Datei | Kennung | Blöcke | Instr. | MIDI-Instr. | Dumps |
|---|---|---|---|---|---|
| `N_ich_will_neues.mmd1` | MMD1 | 17 | 10 | 7 | 2 |
| `N_WOISTDAS_MU80.med` | **MMD3** | 27 | 11 | 6 | 2 |
| `O_Wie_Eine_Marionette.MMD` | MMD1 | 20 | 10 | 4 | 1 |
| `sehnsuchts_blues.MMD1.pp` | MMD1 | 16 | 11 | 8 | 2 |
| `unsere_hände_spielen.MMD` | MMD1 | 28 | 17 | 12 | 4 |

**`.pp` ist kein PowerPacker.** Die Datei beginnt mit `MMD1`, nicht `PP20`.
Ein Entpacker wird für dieses Material nicht gebraucht und wird nicht auf
Vorrat gebaut.

**MMD1 überwiegt (4 von 5)** — ausgerechnet das Format, das Tutka falsch liest.

### 3.1 Tatsächlich benutzte Befehle

| Befehl | Häufigkeit | Bedeutung (Tutka) | Bemerkung |
|---|---|---|---|
| `0C` | 15 089 | Velocity | Daten bis `0x6F` — über den oft genannten Bereich 0–95 hinaus |
| `0F` | 1 904 | Tempo/Sonderwerte | fast nur `FF` = Note stoppen, einmal `FE` = Song stoppen |
| `17` | 2 485 | **undefiniert** | siehe unten |
| `31` | 2 629 | Cmd3x #1 → CC74 | laut `mmdcmd3x`-Tabelle der Datei |
| `0E` | 2 045 | Pan (CC10) | |
| `05` | 25 | **undefiniert** | |
| `09` | 35 | Ticks pro Zeile | Werte 4–10 |
| `10` | 3 | SysEx-Dump senden | genau einmal je Datei, Datenbyte = Dump-Nummer |

### 3.2 Befehl 05/00: der Controller-Mechanismus — GEKLÄRT

Aus der OctaMED-SoundStudio-Dokumentation („The MIDI Cmd 3cxx Window",
amdetails.html), wörtlich:

> „Using a combination of player command types 05 and 00, you can set any MIDI
> controller you choose. Command 05's level is the controller number, command
> 00's the controller value. So if OctaMED came across this in a song:
> `00509` / `00004` then OctaMED would set MIDI controller number 9 to 4."

An den echten Dateien bestätigt: `05 4A` setzt CC74 (Filter-Cutoff), danach
liefert `00 xx` die Werte als glatten Verlauf (64, 66, 68, 70 …).

Die Befehle `31`–`3F` sind die Ein-Zeilen-Abkürzung desselben: Controller-
Nummer und -Typ (Standard/RPN/NRPN, MSB/LSB) stehen in `MMDMIDICmd3x`.

**Messfehler, der dabei auffiel:** Eine erste Befehlsstatistik hatte Befehl `00`
übersprungen (Filter `if cmd != 0`) und damit die Controller-*Werte* nicht
gesehen — allein in `unsere_hände_spielen.MMD` 2 092 Ereignisse. Befehl `00` mit
Datenbyte ≠ 0 ist ein echter Befehl und darf nicht als „leer" behandelt werden.

**Lücke in Tutka:** `commandconversion[5] = CommandNotDefined`. Tutka kennt die
Controller-*Nummer* nicht, verarbeitet aber `00` als Controller-*Wert* — es
sendet also Werte ohne zu wissen, wohin. Filterverläufe landen beim falschen
Controller.

### 3.3 Offene Punkte, die geklärt werden müssen

1. ~~Befehl `0x17`~~ — **GEKLÄRT am 2026-09-30.** Laut OctaMED-Handbuch,
   Anhang A: „**17: CHANGE VOLUME CONTROLLER** (MIDI) — Changes volume
   controller value for the most recently used channel." Also CC7, kanalweise.
   Vom Nutzer im Amiga-Emulator gegengeprüft; er hat es vor allem zum
   Ausblenden benutzt, was zu den gemessenen glatten Abwärtsverläufen passt.
   Die Hypothese einer Verschiebung in Tutkas Tabelle ist damit bestätigt.
   Siehe `02-befehlskatalog.md`.
2. ~~Befehl `0x05`~~ — **GEKLÄRT** (siehe 3.2): Controller-Nummer, im Paar mit
   Befehl `00` als Wert. Steht im Befehlskatalog.
3. **Velocity-Überlauf.** Tutka rechnet `value * 0x80 / 0x60`. Bei gemessenen
   Werten bis `0x6F` ergibt das 148 — über 127. Muss begrenzt werden.
4. **`0x10`-Datenbyte.** Werte 0 und 1 beobachtet. Ob 0- oder 1-basiert
   indiziert wird, ist noch nicht belegt.
5. **Zeilen pro Beat.** `flags2 & 0x1F`, laut Spezifikation `+1`. Eine Datei
   ergibt damit 15 — musikalisch ungewöhnlich, gegen OpenMPT zu prüfen.

### 3.3 Befunde, die den Export direkt bestimmen

- **Notenenden kommen aus `0F FF`, nicht aus Hold/Decay.** 1 544 von 1 545
  `0F`-Befehlen in einer Datei sind `FF` = „Note stoppen". `decay` ist in allen
  fünf Dateien durchgehend 0. Die Notenlängen hängen also vor allem an diesem
  Befehl — der kritische Punkt des MIDI-Exports.
- **Kein einziger Programmwechsel.** `midipreset` und `long_midi_preset` sind
  überall 0. Die Klangzuordnung steckt **ausschließlich in den SysEx-Dumps**.
  Der Export kann keine Programmwechsel aus Instrumentdaten erzeugen.
- **Jedes klingende Instrument hat seinen eigenen MIDI-Kanal.** Gemessen über
  alle fünf Dateien: **null** Kanäle mit zwei klingenden Instrumenten. Vom
  Autor bestätigt. Die im Projekt-Prompt formulierte Sorge über geteilte Kanäle
  trifft auf dieses Material nicht zu.
  Doppelbelegungen kommen vor, aber ausnahmslos als Paar aus einem klingenden
  Instrument und einem mit Lautstärke 0, das der Autor `MidiControlChannel_…`
  genannt hat — bewusste Controller-Spuren.
  **Folge für die Warnung:** Sie darf nur bei zwei *klingenden* Instrumenten auf
  einem Kanal anschlagen. Das Controller-Paar wird als Muster erkannt und als
  Information gezeigt, nicht als Problem.
- **Note-Off über Pattern-Befehl ist bestätigt.** Der Autor: „für das Noteoff
  gab es immer einen pattern-befehl" — deckt sich mit `0F FF`.
- **Spurbreite wechselt je Block** (z. B. 4 bis 20 Spuren in einer Datei). Die
  Pattern-Ansicht darf keine feste Spaltenzahl annehmen.
- **Zusätzliche Befehlsseiten kommen vor** (eine Datei hat eine). Müssen von
  Anfang an gelesen werden.

### 3.4 Die Dumps

Alle gemessenen Dumps beginnen mit `F0 43 00 4C 00 07 00 00` und enden mit
`F7`. `0x43` = Yamaha, `0x4C` = **XG**. Längen 12 970 und 13 154 Bytes.

Dieselben Dumps tauchen in mehreren Songs auf (identische Länge und Kopf) — die
im Prompt gewünschte Hash-Erkennung gleicher Klangsätze ist also unmittelbar
nützlich.

**Gemessen:** Ein „Dump" ist keine einzelne Nachricht. Der 13 154-Byte-Dump
zerfällt in **408 vollständige SysEx-Nachrichten** (408-mal `F0`, 408-mal `F7`,
kein Restbyte). Längen überwiegend 27 Bytes, daneben 52 und 74. Die ersten 407
tragen Model-ID `0x4C` (XG), die letzte `0x49` (**MU80-nativ**).

Folgen:
- Der `.syx`-Export kann den Rohstrom unverändert schreiben — er ist bereits
  eine gültige Folge von `F0…F7`-Nachrichten.
- Beim Einbetten in die MIDI-Datei muss **jede Nachricht ein eigenes
  SysEx-Ereignis** werden, nicht eine einzige Riesennachricht.
- Die MU80-Entschlüsselung (Phase 3) hat es mit ~408 Adressblöcken je Dump zu
  tun. Der genaue Kopfaufbau (Byte-Count- und Adressfelder) ist noch nicht
  entschlüsselt und gehört in Phase 3.

## 4. Gegenprobe am Original: Amiga-Screenshot

Am 2026-09-30 hat der Autor einen Screenshot aus **OctaMED Professional V1.03c**
im Amiga-Emulator geliefert: `O_Wie_Eine_Marionette.MMD`, Block 4, Zeilen 0–34.

Die Datei wurde unabhängig davon geparst und im OctaMED-Anzeigeformat
gerendert. Ergebnis: **in jeder Zelle identisch.**

| | Screenshot | Parser |
|---|---|---|
| Z000 Spur 0 | `E 5 A0000` | `E-5 A0000` |
| Z000 Spur 3 | `C#6 10C50` | `C#6 10C50` |
| Z000 Spur 6 | `00905` | `--- 00905` |
| Z000 Spur 8 | `C#6 20C6F` | `C#6 20C6F` |
| Z004 Spur 1 | `B 3 A0000` | `B-3 A0000` |
| Z008 Spur 5 | `E 8 10C40` | `E-8 10C40` |
| Z001–008 Spur 2 | `01758 … 01757` | `01758 … 01757` |
| Z001–008 Spur 7 | `0177F … 0177D` | `0177F … 0177D` |

Damit sind bestätigt: Notennummerierung samt Oktavlage, Instrumentnummer aus
6 Bit, Befehls- und Datenbyte, die Anordnung Zeile-vor-Spur, die
Blockindizierung.

**Dies ist die Regressionsvorlage für die Pattern-Ansicht.** Erwartete Ausgabe
für Block 4, Zeilen 000–008, Spuren 0–9:

```
000   E-5 A0000 C-4 A0000 C-6 A0C00 C#6 10C50 --- 00000 --- 00000 --- 00905 C-7 10C00 C#6 20C6F C#5 20C6F
001   --- 00000 --- 00000 --- 01758 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177F --- 00000 --- 00000
002   --- 00000 --- 00000 --- 01758 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177F --- 00000 --- 00000
003   --- 00000 --- 00000 --- 01758 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177F --- 00000 --- 00000
004   G#4 A0000 B-3 A0000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
005   --- 00000 --- 00000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
006   --- 00000 --- 00000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
007   --- 00000 --- 00000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
008   D#5 A0000 F#5 A0000 --- 01757 --- 00000 C#8 10C40 E-8 10C40 D#8 10C40 --- 0177D --- 00000 --- 00000
```

### Anzeigeformat

`NOTE` + **1 Hexziffer Instrument** + **2 Hexziffern Befehl** + **2 Hexziffern
Level**. Beispiel `A0C00`: Instrument `A` (= 10), Befehl `0C`, Level `00`.
Die Pattern-Ansicht bildet das nach.

### Was der Screenshot zusätzlich belegt

- **Spurbezogener Kanalzustand, optisch.** Spur 2 hat in Zeile 000 eine Note mit
  Instrument `A` (Kanal 10); ab Zeile 001 stehen dort `17`-Befehle *ohne*
  Instrument. Spur 7 dasselbe mit Instrument `1` (Kanal 1). Zwei Fades
  nebeneinander auf verschiedenen Kanälen — siehe `02-befehlskatalog.md`.
- **Velocity `0x6F`** steht sichtbar in Zeile 000 Spur 8 (`20C6F`). Der
  Überlauf in Tutkas Umrechnung (`0x6F * 0x80 / 0x60` = 148) ist damit kein
  theoretischer Fall.
- **Tempo.** Statuszeile „Tempo = BPM 66/5" deckt sich mit den gemessenen
  `deftempo = 66` und `tempo2 = 5`; `00905` in Spur 6 setzt TPL auf 5.
- **Blockliste** zeigt `002:intro_1` als einzigen benannten Block — die Messung
  fand ebenfalls genau einen Blocknamen.
- **Programmversion.** Titelzeile: *OctaMED Professional V1.03c*, nicht
  SoundStudio. Der Befehlskatalog stammt aus dem SoundStudio-Handbuch. Für `17`
  deckt sich das Verhalten; bei Nachschlagen in dieser älteren Version kann die
  Befehlsliste knapper sein.
