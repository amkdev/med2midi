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

## 1a. Rangfolge der Quellen

Grundsatz, vom Autor formuliert: Die verfügbaren Quellcodes sind mit Vorsicht zu
genießen. Tutka und OpenMPT sind Nachbauten von Einzelkämpfern, entstanden zu
einer Zeit mit kaum verfügbarer Dokumentation — sie hatten weniger in der Hand
als dieses Projekt jetzt. Das hat sich bestätigt: Tutka enthält fünf belegte
Fehler in der Befehlstabelle, OpenMPT kennt Befehl `0x17` überhaupt nicht.

| Rang | Quelle | Charakter |
|---|---|---|
| (0) | OctaMED-Quellcode selbst | nicht veröffentlicht |
| 1 | **Die echten Songdateien** | können nicht lügen |
| 2 | **OctaMED im Amiga-Emulator** | das Programm selbst, kein Nachbau |
| 3 | Kinnunen: `MMD_FileFormat.doc`, Handbuch Anhang A | vom Urheber, aber lückenhaft |
| 4 | UADE `amigasrc/players/med/` (68k) | Originalcode, nur die Player-Routine |
| 5 | Tutka, OpenMPT | Nachbauten, nachweislich fehlerhaft |

**Regel:** Wo Quellen sich widersprechen, entscheidet die Messung an den echten
Dateien. Das ist bisher dreimal so ausgegangen — bei `0x17`, bei `0x05` und bei
der Velocity-Umrechnung. Jede Formatannahme im Code trägt eine Quellenangabe.

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

Die Dumps sehen einander ähnlich — gleiche Länge, gleicher Kopf. **Sie sind
aber alle verschieden:** Über alle sieben Dateien gibt es 11 Dumps und 11
verschiedene SHA-256-Prüfsummen. Jeder Song hat seinen eigenen Klangsatz, und
auch innerhalb eines Songs unterscheiden sich die Dumps. Eine frühere Fassung
dieses Absatzes behauptete das Gegenteil.

Die im Prompt gewünschte Hash-Erkennung ist trotzdem sinnvoll — sie belegt hier
eben, dass nichts doppelt ist.

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
- **Programmversion — zunächst falsch gedeutet, dann geklärt.** Die Titelzeile
  des ersten Screenshots lautet *OctaMED Professional V1.03c*. Daraus wurde
  irrig geschlossen, das Programm sei nicht SoundStudio und der Befehlskatalog
  stamme aus dem falschen Handbuch.

  Weitere Screenshots zeigen dasselbe Programm mit englischer Oberfläche:
  *„OctaMED Soundstudio © 1991–1997 Teijo Kinnunen & Ray Burt-Frost"*,
  *„This is OctaMED SoundStudio v1.03c, for the Amiga"* und im Info-Fenster
  *„OctaMED Soundstudio V1.03c (7.08) (08.02.97)"* neben einem Knopf
  „Übersetzung". Die **deutsche Lokalisierung** schreibt „Professional" in die
  Titelzeile.

  Es ist dasselbe Programm. Das SoundStudio-Handbuch ist die richtige Quelle,
  der Vorbehalt ist zurückgenommen.

  **Die interne Nummer (7.08) ist der Schlüssel:** Kinnunens Spezifikation sagt
  „Note that 'V7' in the following documentation refers to OctaMED Soundstudio
  V1." Alle mit „>= V7" markierten Felder sind in Dateien dieses Programms also
  zu erwarten.

## 5. Formatversion und Instrumentstruktur je Datei

| Datei | Kennung | Mixing | `s_ext_entrsz` | enthält bis |
|---|---|---|---|---|
| `N_WOISTDAS_MU80.med` | MMD3 | **ja** | **24 B** | über die Spezifikation hinaus |
| `N_ich_will_neues.mmd1` | MMD1 | nein | 18 B | `long_repeat`/`long_replen` (V7) |
| `O_Wie_Eine_Marionette.MMD` | MMD1 | nein | 18 B | `long_repeat`/`long_replen` (V7) |
| `sehnsuchts_blues.MMD1.pp` | MMD1 | nein | **10 B** | `output_device` (V5.02) |
| `unsere_hände_spielen.MMD` | MMD1 | nein | 18 B | `long_repeat`/`long_replen` (V7) |

**Woher stammt die MMD3-Datei? — offen, aber mit Indizien.**

Beobachtung: Die einzige MMD3-Datei ist genau die mit gesetztem `FLAG2_MIX`.
Daraus wurde zunächst geschlossen, MMD3 hänge am Mixing-Modus, und das sei
„am Material bestätigt". **Das war eine Überinterpretation bei n = 1.** Mit
einer einzigen MMD3-Datei lassen sich zwei Erklärungen nicht trennen:

1. SoundStudio schreibt MMD3, weil Mixing an ist (Kinnunens Begründung).
2. Die Datei stammt aus der **Windows-Version** (MED SoundStudio V2.1), die
   der Autor ebenfalls benutzt hat — seine eigene Vermutung.

**Indizien sprechen für (2):** siehe den entschlüsselten `InstrExt`-Zusatz
unten sowie den Songnamen `'<ohne Namen>'` — ein *deutscher* Vorgabename,
während die Windows-Version englische Menüs hat. Das passt zu einem Song, der
auf dem deutschen Amiga entstand und später unter Windows neu gespeichert
wurde.

Zur Klärung genügen weitere MMD3-Dateien: Findet sich eine **ohne** Mixing-Flag,
ist (1) widerlegt. Findet sich eine mit 18-Byte-`InstrExt`, stammt sie vom
Amiga.

**`InstrExt` hat keine feste Größe.** Gemessen: 10, 18 und 24 Bytes je Eintrag.
Die Spezifikation dokumentiert 18. Die MMD3-Datei führt **24** — sechs Bytes
mehr als beschrieben, also eine undokumentierte Erweiterung.

Folge für den Parser, wie die Spezifikation es ausdrücklich verlangt: immer
`s_ext_entrsz` lesen, Felder nur anfassen, wenn die Größe sie abdeckt, und
überzählige Bytes überspringen statt zu deuten. Dasselbe gilt für
`i_ext_entrsz`. Bei `sehnsuchts_blues` existiert `long_midi_preset` gar nicht.

Randnotiz: `i_ext_entrsz` ist in **allen** Dateien 42, die Spezifikation
dokumentiert 40 (`name[40]`). Diese zwei Zusatzbytes schreibt auch die
Amiga-Version; sie taugen nicht zur Unterscheidung.

**Gemessen:** Sie sind in allen fünf Dateien, bei jedem Instrument,
durchgehend `00 00`. Keine Information. Die naheliegende Erklärung: `name[40]`
soll nullterminiert sein — bei 40 Zeichen bliebe kein Platz dafür, also 41
Bytes, aufgerundet auf 42 wegen der Regel „always align everything to even
boundaries".

Die Vermutung, hier seien Bytes für neue Befehle hinzugekommen, trägt nicht.
**Neue Befehle brauchen keinen zusätzlichen Platz:** Ab MMD1 ist das
Befehlsfeld der Note ein volles Byte (`cccccccc`), benutzt sind `00`–`3F` —
Raum für 192 weitere ohne jede Strukturänderung. In MMD0 hatte der Befehl nur
4 Bit; genau das nennt Kinnunen als Grund für MMD1.

Vorgesehene Erweiterungsstellen im Format sind stattdessen:
`MMDMIDICmd3x.num_of_settings` („currently set to 15 … could be > 15 in the
future"), die `BlockCmdPageTable` für mehrere Befehle je Note, und
`s_ext_entrsz` für Instrumentfelder — wo die Windows-Version auch tatsächlich
erweitert hat.

### Der `InstrExt`-Zusatz in der MMD3-Datei — entschlüsselt

Die sechs Bytes jenseits der dokumentierten 18 sind nicht leer. Byte 19
(Offset 18) gemessen gegen das Amiga-Feld `svol`:

| `svol` (0–64) | Byte 19 |
|---|---|
| 47 | 94 |
| 49 | 98 |
| 48 | 96 |
| 64 | 127 |
| 32 | 64 |
| 50 | 100 |

Die Beziehung ist **`svol × 2`, gedeckelt bei 127** — alle sechs Werte passen.
Bei Instrumenten ohne MIDI-Kanal steht 0. Es ist also die
**Instrumentlautstärke im MIDI-Bereich 0–127**, während `svol` im Amiga-Bereich
0–64 bleibt. Bytes 20–24 sind in dieser Datei durchgehend null.

Ein Programm, das `InstrExt` um ein MIDI-skaliertes Lautstärkefeld erweitert,
ist MIDI-nativer als die Amiga-Version — und die Amiga-V7.08 schreibt diese
Bytes nachweislich nicht (18 Bytes). Die MMD3-Datei stammt somit von einem
**späteren Programm als OctaMED SoundStudio V1.03c für Amiga**.

**Folge für den Export:** Wo dieses Feld existiert, ist es der genauere Wert
für die Anfangslautstärke als `svol × 2` aus dem Amiga-Feld — es ist bereits
die Zahl, die das schreibende Programm gesendet hätte. Wo es fehlt, wird aus
`svol` gerechnet.

## Zur Produktabstammung

| Programm | Format | Anmerkung |
|---|---|---|
| MED V2.1 | MMD0 | |
| OctaMED Professional | MMD1 | neue Blockstruktur |
| OctaMED V5+ | MMD2 | Sections, Playseqs |
| OctaMED SoundStudio V1 | MMD3 | intern **V7** — daher „V7" in der Spezifikation |

Der Autor besitzt SoundStudio V1.03c. Laut dessen eigenem Startfenster war es
ab Juli 96 kommerziell und wurde im Februar 97 als Freeware freigegeben
(„released as freeware far earlier than intended … due to the high amounts of
piracy"). Das erklärt seine Erinnerung an zwei Bezugsquellen, ohne dass es zwei
verschiedene Programme gewesen sein müssen.

## 6. Die MMD3-Dateien sind strukturell verkürzt

Der Autor konnte eine MMD3-Datei in OctaMED SoundStudio V1.03c auf dem Amiga
**nicht laden**. Die Messung liefert einen guten Kandidaten für den Grund.

Die Spezifikation gibt `MMD0exp` mit **84 Bytes** an; letztes Feld ist
`ULONG tag_end`. Gemessen, Abstand vom `expdata`-Zeiger bis zum Dateiende:

| Datei | Kennung | verfügbar | |
|---|---|---|---|
| `N_WOISTDAS_MU80.med` | MMD3 | **80** | `tag_end` fehlt |
| `final_manchmaltriffteinlächeln2001.med` | MMD3 | **80** | `tag_end` fehlt |
| `final_soverloren.med` | MMD3 | **80** | `tag_end` fehlt |
| alle vier MMD1-Dateien | MMD1 | 84 | vollständig |

`modlen` entspricht bei allen Dateien exakt der Dateigröße, der Amiga reserviert
also genau so viel Speicher. Ein Lader, der die dokumentierten 84 Bytes liest,
greift damit **vier Bytes hinter das Modul**.

Der Parser dieses Projekts liest `tag_end` nicht und prüft ohnehin jeden
Zugriff gegen die Dateigröße — das war Glück, nicht Vorsicht. Er meldet den
Fall jetzt als Warnung.

### Was die Amiga-Playroutine von der Erweiterung weiß: nichts

`MED_PlayRoutine.i` relociert in `BlockInfo` genau vier Zeiger — `hldata`,
`blockname` (`blocknamelen` wird übersprungen) und `pagetable` — und hört dann
auf. Das fünfte Langwort, in dem die Windows-Version `cmdExtTableOffset`
ablegt, kennt sie nicht.

Die Amiga-Version kann die 7-Bit-Lautstärke also gar nicht auswerten. Für den
Export dieser drei Dateien ist damit allein die Windows-Semantik maßgeblich.

## 7. Zeitrechnung am Original bestätigt

Der Autor hat das Tempo-Fenster von OctaMED für `O_Wie_Eine_Marionette.MMD`
fotografiert. Alle drei Felder decken sich mit dem, was der Parser liest:

| Feld | OctaMED | Parser | Herkunft |
|---|---|---|---|
| Tempo | 066 | 66 | `MMD0song.deftempo` |
| TPL | 005 | 5 | `MMD0song.tempo2` |
| LPB | 015 | 15 | `flags2 & 0x1F` = 14, **+1** |

Damit ist die `+1`-Umrechnung des LPB-Feldes belegt — die Spezifikation sagt
„0 = 1 line, $1F = 32 lines", und 15 ist kein Lesefehler, sondern die
Einstellung des Autors für dieses langsame Stück.

Zeilendauer im BPM-Modus:

```
Sekunden pro Zeile = 60 / (BPM × LPB)
                   = 60 / (66 × 15) = 0,0606 s
```

Ein Block mit 512 Zeilen dauert damit 31 Sekunden.

**Noch offen:** Tempowechsel per Befehl `0F` und `09` während des Stücks. Die
Zeitanzeige der App rechnet mit dem Grundtempo; die Player-Simulation der
Phase 2 muss die Wechsel mitführen.
