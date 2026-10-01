# Befehlskatalog

Maßgebliche Quelle: **OctaMED-SoundStudio-Handbuch, Anhang A**
<https://retro.pasz.nl/resources/octamed-soundstudio-manual/appendices/app-a/>

Vom Nutzer am 2026-09-30 gefunden und im Amiga-Emulator gegengeprüft. Diese
Quelle löst alle vorher offenen Befehle auf und korrigiert Tutka an fünf
Stellen.

## Grundsatz: jeder Befehl hat zwei Bedeutungen

Dieselbe Befehlsnummer bedeutet für **Sample-Instrumente** etwas anderes als für
**MIDI-Instrumente**. Das ist der Grund, warum OpenMPT und Tutka sich
widersprechen: OpenMPT implementiert die Sample-Seite, Tutka die MIDI-Seite.

Für dieses Projekt gilt durchgehend die MIDI-Seite. Die Sample-Deutung wird im
Katalog mitgeführt, damit die Pattern-Ansicht erklären kann, was ein Befehl
täte — aber der Export benutzt sie nicht.

## MIDI-Befehle (die für dieses Projekt geltende Spalte)

| Nr. | Bedeutung | Anmerkung |
|---|---|---|
| `00` | Controller-**Wert** | Paar mit `05`. Datenbyte ≠ 0 heißt: echter Befehl, kein leeres Feld |
| `01`/`02` | Pitchbend auf/ab | 8 × Level Schritte je Tick |
| `03`/`13` | Pitchbend absolut setzen | Level als Vorzeichenwert, −128…127 |
| `04` | Modulationsrad (CC1) | |
| `05` | Controller-**Nummer** | Paar mit `00` |
| `08` | **nur** Hold setzen | Handbuch: „decay can't be used with MIDI instruments" |
| `09` | Ticks pro Zeile (TPL) | Level `$01`–`$20` |
| `0A` | **Polyphonic Aftertouch** | *nicht* Velocity — Tutka irrt hier |
| `0C` | Velocity / Lautstärke | Amiga-Bereich 0–64 → MIDI 0–127 |
| `0D` | Channel Aftertouch | Kanal der Spur (siehe unten) |
| `0E` | Pan | Level `$00`–`$7F` |
| `0F` | Tempo und Sonderfunktionen | siehe unten |
| `10` | SysEx-Nachricht senden | Level = Nachrichtennummer |
| `17` | **Volume Controller (CC7)** | Kurzform für `05 07` + `00 xx`; Kanal der Spur |
| `1C` | MIDI-Preset wechseln | Programmwechsel |
| `1D` | Sprung zum nächsten Playseq-Eintrag | mit Zeilennummer |
| `1F` | Note Delay und Retrigger | |
| `31`–`3F` | frei belegbarer Controller | Nummer und Typ aus `MMDMIDICmd3x`; Typ Standard/RPN/NRPN, MSB/LSB |

### Sonderwerte von `0F`

| Level | Wirkung |
|---|---|
| `F1` | Note zweimal spielen (Retrigger) |
| `F2` | Note um halbe Zeile verzögern |
| `F3` | Note dreimal spielen |
| `F4` | Note um ein Drittel Zeile verzögern |
| `F5` | Note um zwei Drittel Zeile verzögern |
| `F7` | warten, bis Nachrichten gesendet sind |
| `FA`/`FB` | Hold-Pedal an / aus |
| `FE` | Song anhalten |
| `FF` | **Note auf der aktuellen Spur stoppen** |

`0F FF` ist in den Testdateien der Hauptmechanismus für Note-Off — vom Autor
bestätigt: „für das Noteoff gab es immer einen pattern-befehl".

## Zustandsabhängige Befehle — der Bezugsrahmen ist die Spur

`0A`, `0D` und `17` wirken laut Handbuch nicht auf das Instrument ihrer eigenen
Zeile, sondern:

> `0A`: „Changes the polyphonic aftertouch of **the most recent note**."
> `0D`: „Sends a channel aftertouch message to **the most recently used
> channel**."
> `17`: „Changes the volume controller value for **the most recently used
> channel**."

Das Handbuch sagt nicht ausdrücklich, in welchem Bezugsrahmen „most recently"
gilt. **An den echten Daten gemessen: pro Spur.**

`O_Wie_Eine_Marionette.MMD`, Block 4, Zeile 1 — vier `17`-Befehle gleichzeitig:

| Spur | letztes Instrument auf dieser Spur | Kanal | Wert |
|---|---|---|---|
| 2 | 10 | 10 | `58` |
| 7 | 1 | 1 | `7F` |
| 10 | 2 | 2 | `7F` |
| 14 | 3 | 3 | `70` |

Über die Zeilen 1–5 laufen die Werte `58,58,58,57,57` / `7F,7F,7F,7E,7E` /
`70,70,70,6F,6F` — ein gemeinsames Ausblenden auf vier Kanälen mit je eigenem
Ausgangspegel.

Bei **globalem** Bezug würden alle vier denselben Kanal treffen und sich
überschreiben; der Song wäre unspielbar. Der Bezug ist also die Spur, was auch
das Handbuch-Beispiel zu `05`/`00` nahelegt (Befehle auf `---`-Zeilen unter
einer Note mit Instrument 03 senden `$B0`, also Kanal 1).

Das deckt sich mit dem Einwand des Autors: Bei multitimbraler Nutzung wäre ein
globaler „zuletzt benutzter Kanal" unbrauchbar.

**Folge für die Player-Simulation:** Sie führt **pro Spur** den zuletzt
gesetzten Kanal, die zuletzt gespielte Note und die zuletzt mit `05` gewählte
Controller-Nummer mit. Laut Handbuch gilt zusätzlich: „Remember that each MIDI
channel has its own controller number" — die mit `05` gewählte Nummer ist also
Zustand **pro Kanal**, nicht pro Spur.

## Mehrere Spuren pro Instrument = Mehrstimmigkeit

In `O_Wie_Eine_Marionette.MMD` hat Block 4 zwanzig Spuren, aber nur vier
Instrumente: Spuren 0–2 auf Instrument 10, Spuren 3–7 auf Instrument 1,
Spuren 8–10 und 12 auf Instrument 2, Spuren 11, 13, 14 auf Instrument 3.

Der Autor hat mehrere Spuren pro Instrument für Akkorde benutzt. Die im
Projekt-Prompt gewählte Voreinstellung „eine MIDI-Spur pro MED-Instrument"
fasst diese Spuren korrekt zusammen.

## Tutkas Fehler

Tutkas `commandconversion`-Tabelle (`conversion.cpp:141–179`) ist **dezimal**
indiziert. 14 Einträge stimmen, fünf nicht:

| Befehl | Handbuch (MIDI) | Tutka | Art |
|---|---|---|---|
| `05` | Controller-Nummer | `NotDefined` | fehlt — Controller-Werte landen ohne Nummer |
| `0A` | Polyphonic Aftertouch | `CommandVelocity` | falsch |
| `16` | Repeat Lines (Loop) | `MidiControllers + 7` (CC7) | falsch |
| `17` | Volume Controller (CC7) | `NotDefined` | fehlt |
| `1C` | MIDI-Preset wechseln | `NotDefined` | fehlt |
| `0F F7/FA/FB` | Suspend, Hold-Pedal | — | fehlt |

Tutka hat CC7 also um genau eine Stelle zu tief eingeordnet.

## Weitere Befehle (Sample-Seite, für die Erklärfunktion)

`00` Arpeggio · `05` Slide Pitch and Fade · `0A` Volume Slide (veraltet) ·
`0D` Volume Slide · `0E` Synth Jump · `11`/`12` Pitch einmalig auf/ab ·
`14` ProTracker-Vibrato · `15` Finetune setzen · `16` Repeat Lines (Loop) ·
`18` Cut Note (Lautstärke auf 0, kein Note-Off) · `19` Sample-Startoffset ·
`1A`/`1B` Lautstärke einmalig auf/ab · `1E` Zeile wiederholen ·
`20`–`2F` Mix-Modus (für dieses Projekt ohne Belang)

## Befehl `0C` (Velocity) — am Original gemessen

**Gemessen im Amiga-Emulator mit MIDI Monitor** (2026-10-01). Drei Ausgänge,
nicht einer:

| Datenbyte | Wirkung |
|---|---|
| `0x00`–`0x40` | Velocity, skaliert |
| `0x41`–`0x7F` | **nichts** — es gilt weiter die Grundlautstärke des Instruments |
| `0x80`–`0xC0` | setzt die Grundlautstärke (Wert − `0x80`) und spielt damit |

Das deckt sich mit dem Assembler der Playroutine (`MED_PlayRoutine.i`, `.f_0c`):

```asm
.volhex:
    CMP.B   #64,D0
    BHI.S   .go_nocmd      ; über 64: Befehl verwerfen
.plr_setvol:
    MOVE.B  D0,trk_prevvol(A5)
```

Der Zweig steht dort in einem `IFNE CHECK`, und KONEYs Demo-Fassung setzt
`CHECK EQU 0`. Daraus wurde zwischenzeitlich geschlossen, die Prüfung sei
belanglos — die Messung widerlegt das. Im echten OctaMED ist sie aktiv.

**Warum die erste Messung irreführte:** `0C41`–`0C7F` ergab Velocity 127. Das
sah nach Deckelung aus, war aber die Grundlautstärke 64 des Testinstruments,
die nach dem Verwerfen weitergalt.

### Die Skalierung

```
velocity = ⌊wert × 127 / 64⌋
```

Ganzzahlig abgeschnitten identisch mit „verdoppeln, von null gezählt"
(`2v − 1` für `v = 1…64`), weil `v × 127/64 = 2v − v/64`. Beide Beschreibungen
meinen dieselbe Funktion. Abschneiden, nicht runden.

### Drei Lesarten des Datenbytes

| Lesart | wann | Wert |
|---|---|---|
| `.sevenBit` | Block trägt eine Befehlserweiterung | Byte ist bereits 0–127, **keine** Skalierung, **keine** 64er-Grenze |
| `.hexadecimal` | `FLAG_VOLHEX` gesetzt | Byte ist der Wert |
| `.decimal` | `FLAG_VOLHEX` nicht gesetzt | Halbbytes sind Dezimalziffern: `0x40` = 40 |

Die Dezimallesart ist am Original gemessen: Dieselben Patterndaten ergeben
`0x40` → 127 im Hex-Modus und → 79 im Dezimalmodus. Der Anzeigemodus wird also
beim Abspielen ausgewertet. Der Assembler bestätigt es:

```asm
    BTST    #4,msng_flags(A4)     ; FLAG_VOLHEX
    BNE.S   .volhex
    LSR.B   #4,D0 / MULU #10,D0   ; oberes Halbbyte × 10
    MOVE.B  D4,D1 / AND.B #$0f,D1 ; unteres Halbbyte
    ADD.B   D1,D0                 ; BCD
```

Bei `.sevenBit` entfällt die 64er-Grenze — sonst wären in den MMD3-Dateien
drei Viertel aller `0C`-Befehle wirkungslos. Quelle: OpenMPT `Load_med.cpp`,
dritte Verzweigung bei `0x0C`.

### Wirkung auf das Testmaterial

| Datei | Lesart | `0C` gesamt | wirkungslos | versch. Velocities |
|---|---|---|---|---|
| `N_WOISTDAS_MU80.med` | 7 Bit | 2819 | 0 | 58 |
| `final_manchmaltriffteinlächeln2001.med` | 7 Bit | 5000 | 0 | 42 |
| `final_soverloren.med` | 7 Bit | 1875 | 0 | 6 |
| `N_ich_will_neues.mmd1` | hex | 3370 | **241 (7 %)** | 29 |
| `O_Wie_Eine_Marionette.MMD` | dezimal | 3066 | 174 (5 %) | 51 |
| `sehnsuchts_blues.MMD1.pp` | dezimal | 3785 | 5 | 50 |
| `unsere_hände_spielen.MMD` | dezimal | 2041 | 1 | 40 |

In `N_ich_will_neues.mmd1` bewirkten 241 Velocity-Befehle nichts: die Werte 68,
74, 80 und 96 liegen über 64. Dort galt jeweils die Grundlautstärke weiter.
Die Diagnose meldet es ab 25 %.

### Umsetzung

`CommandCatalog.volumeCommand(data:encoding:)` gibt `.velocity`,
`.setDefaultVolume` oder `.ignored` zurück. Die Player-Simulation führt die
Spurlautstärke mit (entspricht `trk_prevvol` im Assembler) und lässt sie bei
`.ignored` unverändert.

### Nicht zu verwechseln: `svol`

Die Instrument-Grundlautstärke `svol` (0–64) wird **verdoppelt ohne Nullbasis**:
Das undokumentierte Feld der 24-Byte-`InstrExt` zeigt 47→94, 49→98, 48→96,
64→127, 32→64, 50→100. Mit `⌊v × 127/64⌋` ergäbe 47 den Wert 93, gemessen ist
94. Zwei Größen, zwei Formeln.

## Sample-Instrumente kommen vor — anders als im Projekt-Prompt angenommen

Der Projekt-Prompt sagt „ausschließlich MIDI-Instrumente, keine Samples". In
zwei der sieben Dateien stimmt das nicht ganz:

| Datei | Instrument ohne MIDI-Kanal | Noten | Sampledaten |
|---|---|---|---|
| `final_manchmaltriffteinlächeln2001.med` | 3, 5 | 8, 2 | keine |
| `final_soverloren.med` | 9 | 189 | keine |

Alle drei haben **keinen Sampledatensatz** in der Datei. Die Spezifikation
erklärt das bei `smplarr`: „This pointer is zero in OctaMED Pro MMD1 songs. In
this case, OctaMED Pro loads the instruments from disk(s)." Die Samples lagen
als eigene Dateien daneben.

Diese Noten erzeugen keine MIDI-Ausgabe. Damit sie nicht stillschweigend
verschwinden, meldet die Diagnose sie als Warnung.

## Befehl `0A`: vermutlich aus alter Gewohnheit gesetzt

In `final_manchmaltriffteinlächeln2001.med` steht `0A` **1478-mal**, aber nur
mit drei verschiedenen Werten: **0, 1 und 15**; 78 % neben einer Note.
Beispielverlauf über aufeinanderfolgende Zeilen: `1 0 1 0 1 0 1 0`.

Polyphoner Aftertouch — die MIDI-Bedeutung laut Anhang A — wäre ein Verlauf
über 0–127. Das Muster passt eher zur Sample-Bedeutung („Volume Slide,
Nibble-Geschwindigkeit"), die der Autor aus älteren OctaMED-Versionen kannte.
Das Instrument dahinter liegt aber auf MIDI-Kanal 6, OctaMED hat also
polyphonen Aftertouch mit Wert 15 gesendet — praktisch unhörbar.

Die Diagnose meldet solche Fälle: ein Befehl mit sehr wenigen, kleinen Werten
passt oft nicht zu seiner MIDI-Bedeutung.

## Notenlängen: Hold, `0F FF` und Blockgrenzen

Der im Projekt-Prompt als kritisch markierte Punkt. Stand nach Messung und
Auskunft des Autors.

### Hold ist in Ticks

> „You can change the default note length (**in ticks**) for an instrument by
> setting the Hold value in the instrument properties window… The default note
> length is usually zero, which means **play until a stop message is sent**."

Beispiel aus derselben Quelle: bei 4 Zeilen pro Beat und 6 Ticks pro Zeile
ergibt `hold = 6` eine Notenlänge von einer Zeile, also einem Viertelbeat.

Das Handbuch (Anhang A, Befehl 08 MIDI) ergänzt: „the whole command level can be
used to set hold. So hold values above 15 are possible (right up to 255)."
Decay gibt es bei MIDI nicht — „because with MIDI, the volume of an already
played note can't be altered".

### Zwei Wege zum Notenende, sauber getrennt

Gegenprobe über alle sieben Dateien: `0F FF` steht fast ausschließlich auf
Spuren, deren Instrument `hold = 0` hat.

| Datei | `0FFF` bei `hold = 0` | bei `hold > 0` |
|---|---|---|
| `N_ich_will_neues.mmd1` | 1538 | 3 |
| `sehnsuchts_blues.MMD1.pp` | 69 | 2 |
| `O_Wie_Eine_Marionette.MMD` | 61 | 5 |
| `final_soverloren.med` | 50 | 32 |
| `unsere_hände_spielen.MMD` | 37 | 4 |
| `N_WOISTDAS_MU80.med` | 44 | 1 |
| `final_manchmaltriffteinlächeln2001.med` | 36 | 0 |

- `hold > 0` → die Länge steht fest, kein Befehl nötig.
- `hold = 0` → die Note klingt, bis ein `0F FF` kommt.

### Note-Offs stehen im *nächsten* Block

Auskunft des Autors:

> „das mit dem noteoff in der nächsten pattern hat einen grund. wenn ich sie
> ganz am schluss als letzten befehl genutzt hätte, wäre die note vor dem ende
> der pattern beendet worden"

Ein `0F FF` in Zeile 0 eines Blocks beendet also die Note aus dem **vorigen**
Block. Beispiel `final_soverloren.med`, Block 27: Zeile 0 trägt `0FFF` auf acht
Spuren gleichzeitig.

**Folge für die Player-Simulation (Phase 2):** Blöcke dürfen nicht einzeln
betrachtet werden. Die Simulation läuft die Songreihenfolge durch und führt
offene Noten über Blockgrenzen mit. Sonst werden lange Töne am Blockende
abgeschnitten — genau der Fehler, den der Autor damals umgangen hat.

Ebenfalls zu beachten: Eine Zelle kann Note **und** `0F FF` zugleich tragen
(Block 27, Zeile 0, Spur 6: `D-4 6 0FFF`). Die Reihenfolge — erst alte Note
beenden, dann neue spielen — ist noch nicht am Original geprüft.

## Instrumentnummer ohne Note — vermutlich Editier-Überbleibsel

In den Pattern-Daten stehen tausende Zellen, die eine Instrumentnummer tragen,
aber keine Note. Vermutung des Autors: Beim Löschen einer Note in OctaMED blieb
die Instrumentnummer stehen.

Gemessen, zwei Sorten:

| Datei | nur Instrument | davon **mit** Befehl | „rein" |
|---|---|---|---|
| `O_Wie_Eine_Marionette.MMD` | **0** | — | **0** |
| `N_ich_will_neues.mmd1` | 4167 | 3691 | 476 |
| `sehnsuchts_blues.MMD1.pp` | 1321 | 343 | 978 |
| `unsere_hände_spielen.MMD` | 1986 | 4 | 1982 |
| `N_WOISTDAS_MU80.med` | 2792 | 124 | 2668 |
| `final_manchmaltriffteinlächeln2001.med` | 4001 | 52 | 3949 |
| `final_soverloren.med` | 3387 | 11 | 3376 |

**Instrument mit Befehl** ist Absicht: So zielt man einen Befehl auf einen
bestimmten Kanal, ohne eine Note zu spielen. Bei `N_ich_will_neues.mmd1` sind
das 3691 von 4167 Fällen.

**Instrument ohne alles** stützt die Vermutung des Autors:

- **Keine einzige Spur** trägt die Nummer durchgehend (0 von 44, 0 von 84 …).
  Eine Automatik des Programms würde durchlaufen.
- `O_Wie_Eine_Marionette.MMD` hat **null** solcher Zellen. Wäre es
  Programmverhalten, müsste es dort ebenso auftreten.
- Nur 15–38 % stehen direkt hinter einer Note; der Rest sitzt verstreut.

### Folge für die Player-Simulation — geprüft, unkritisch

Eine Instrumentzelle ändert den Instrumentbezug der Spur und damit potenziell
den Kanal, auf den `17`, `0A` und `0D` wirken. Ein Überbleibsel könnte also
einen Controller auf den falschen Kanal leiten.

Gemessen: In allen sieben Dateien **null Fälle**, in denen eine reine
Instrumentzelle den Kanal wechselt und danach ein kanalbezogener Befehl folgt.
Kanalwechsel durch solche Zellen gibt es (290, 9, 2), aber nie mit Folgen.

**Offen:** Ob OctaMED den „most recently used channel" bereits beim Schreiben
der Instrumentnummer setzt oder erst beim Spielen einer Note. Da es in diesem
Material nirgends greift, ist es nicht dringend — für einen vollständigen
Export aber zu klären.

## Der Originalcode der Playroutine

Gefunden am 2026-10-01: <https://github.com/KONEY/octamed_playroutines_amiga> —
68k-Assembler der OctaMED-Playroutine, neuer aufbereitet als die Fassung in
UADE. Die Datei `med/MED_PlayRoutine.i` enthält die Befehlsauswertung.

**Einschränkung:** Zeile 25 der Datei: `KONEY Version 1.2 | 30.04.2022 |
NO MORE AURA/MIDI CODE | BIG REFACTOR`. Der MIDI-Ausgabepfad wurde entfernt;
übrig sind nur Datenstrukturen (`trk_prevmidich`, `ext_midipsets`). Die
Befehlsauswertung davor ist aber gemeinsam und damit verwertbar.

### Befehl `0C` im Original

```asm
.f_0c:
    MOVE.B  D4,D0
    BPL.S   .plr_nosetdefvol      ; Bit 7 gesetzt?
    AND.B   #$7F,D0               ; ja: Grundlautstärke setzen
    IFNE CHECK
      CMP.B #64,D0
      BGT.S .go_nocmd
    ENDC
    MOVE.B  D0,inst_svol(A4,D1.W) ; neue Grundlautstärke
    BRA.S   .plr_setvol           ; und damit auch spielen

.plr_nosetdefvol:
    BTST    #4,msng_flags(A4)     ; FLAG_VOLHEX
    BNE.S   .volhex
    LSR.B   #4,D0                 ; oberes Halbbyte
    MULU    #10,D0                ; × 10
    MOVE.B  D4,D1
    AND.B   #$0f,D1               ; unteres Halbbyte
    ADD.B   D1,D0                 ; BCD-Dekodierung
.volhex:
    IFNE CHECK
      CMP.B #64,D0
      BHI.S .go_nocmd             ; über 64: Befehl verwerfen
    ENDC
.plr_setvol:
    MOVE.B  D0,trk_prevvol(A5)
```

**Bestätigt:**

- Die **BCD-Dekodierung** bei nicht gesetztem `FLAG_VOLHEX` — genau
  `(byte >> 4) × 10 + (byte & 0x0F)`, wie aus der Messung erschlossen und wie
  OpenMPT es implementiert.
- `FLAG_VOLHEX` ist **Bit 4** von `msng_flags`, also `0x10`.
- Werte ab `0x80` setzen `inst_svol` (die Grundlautstärke) **und** spielen die
  Note damit — deckt sich mit Handbuch und der Beobachtung des Autors
  (`0C90` → Lautstärke 16).
- `0F FF` ruft `_ChannelOff` (Zeile ~1302).

**Offen geblieben: Werte über 64.** Der Zweig, der den Befehl verwirft
(`BHI .go_nocmd`), steht in `IFNE CHECK`, und `med_feature_control.i` setzt
`CHECK EQU 0`. In der ausgelieferten Fassung wird der Wert also ungeprüft
durchgereicht — weder verworfen noch gedeckelt.

Die Messung des Autors (`0C41`–`0C7F` → Velocity 127) trennt die Deutungen
nicht: Beim Deckeln kommt 127 heraus; beim Verwerfen bliebe die vorige
Lautstärke stehen, und die war im Test vermutlich die Grundlautstärke 64 — was
ebenfalls 127 ergibt.

**Unterscheidender Test:** Instrument-Grundlautstärke auf **16** stellen, dann
`0C7F` spielen.

| gesendete Velocity | Bedeutung |
|---|---|
| 127 | wird gedeckelt (aktuelle Umsetzung) |
| 31 | wird verworfen, die alte Lautstärke bleibt |

Bis dahin bleibt das Deckeln: OpenMPT macht es ebenso
(`std::min(param & 0x7F, 64)`), und die Messung widerspricht nicht.

### Was die Routine sonst noch belegt

`med/loadmod.a` erkennt **alle vier Formatversionen** (`MMD0`–`MMD3`,
Zeilen 97–103) und kennt Befehlsseiten (`numpages`, `pagetable`). Die
Amiga-Version des Autors kann MMD3-Dateien also laden — die 7-Bit-Frage lässt
sich dort prüfen, ohne die Windows-Version zum Laufen zu bringen.

## Zeitrechnung und Hold — aus der Playroutine, am Original gemessen

### Die Tickrate

`MED_PlayRoutine.i`, `_SetTempo` und `_IntHandler`.

```asm
.ST_bpm:                       ; BPM-Modus
    MOVE.B  msng_flags2(A0),D1
    AND.W   #$1F,D1
    ADDQ.B  #1,D1              ; LPB = (flags2 & 0x1F) + 1
    MULU    D1,D0              ; Tempo × LPB
    MOVE.L  bpmdiv,D1          ; bpmdiv = 3546895/2 = 1773447
    DIVU    D0,D1              ; Periode

.calctempo:                    ; SPD-Modus, Tempo > 10
    MOVE.L  timerdiv,D1        ; timerdiv = 470000
    DIVU    D0,D1              ; Periode = timerdiv / Tempo
```

Im **BPM-Modus** teilt der Interrupt-Handler zusätzlich durch vier:

```asm
_IntHandler:
    SUBQ.B  #1,bpmcounter
    BLE.S   .plr_bpmcnt0
    BRA.W   .plr_exit          ; sonst raus
    .plr_bpmcnt0:
    MOVE.B  #4,bpmcounter
```

Mit dem PAL-E-Takt 709 379 Hz folgt daraus

```
Tickrate = 709379 × (Tempo × LPB) / (1773447 × 4) = (Tempo × LPB) / 10  Hz
```

Eine Zeile dauert `TPL` Ticks — `mmd_counter` zählt bis `tempo2`:

```
Zeilendauer = TPL × 10 / (Tempo × LPB)
```

**Die verbreitete Formel `60 / (BPM × LPB)` stimmt nur bei `TPL = 6`.**

| Datei | TPL | nach `60/(BPM×LPB)` | richtig |
|---|---|---|---|
| Testsong (BPM 33, LPB 8) | 6 | 227,27 ms | 227,25 ms |
| `O_Wie_Eine_Marionette.MMD` (BPM 66, LPB 15) | **5** | 60,61 ms | **50,50 ms** |

Bei Marionette liegt die alte Formel um 20 % daneben — ein 512-Zeilen-Block
dauert 25,9 s statt 31,0 s. Für die Tempo-Map des Exports wäre das ein echter
Fehler gewesen.

**Am Original geprüft:** Ein 64-Zeilen-Block lief in **14,547 s** durch
(Note On 18:29:38.399 → Note Off 18:29:52.946), bei BPM 33, TPL 6, LPB 8. Das
sind 227,297 ms je Zeile; die Formel sagt 227,252 ms — **0,02 % Abweichung**.

Im **SPD-Modus** entfällt der Vierer-Teiler. Tempo 33 ergibt Periode
`470000/33 = 14242`, also 49,81 Ticks je Sekunde — die klassischen 50 Hz.
Für Tempo ≤ 10 gibt es eine Tabelle der SoundTracker-Tempi (2417, 4833, 7250 …);
im Testmaterial kommt das nicht vor.

Alle sieben Songdateien des Autors stehen im **BPM-Modus**.

### Hold zählt Ticks

`DoFX` ruft `HoldAndFade` einmal je Spieltick; dort wird `trk_noteoffcnt`
um eins verringert. Hold ist also eine Tickzahl.

Messung des Autors, Testsong im SPD-Modus (Vorgabe eines neuen Songs,
Tempo 33 → Tick 20,08 ms):

| `hold` | Notenlänge |
|---|---|
| 1 | 1,656 s |
| 32 | 2,276 s |
| **Differenz** | **0,620 s** |

31 Ticks × 20,08 ms = 0,622 s — Abweichung 0,4 %. Beide Messungen zerlegen sich
als `1,634 s + hold × Tickdauer`; der gleichbleibende Sockel war das, was die
Note sonst beendet hat. **Hold wirkt zusätzlich, nicht ausschliesslich** — und
war deshalb im ersten Versuch fast unsichtbar.

In den Songs des Autors steht `hold` meist auf 6 bei `TPL = 6`, also genau eine
Zeile; 12 sind zwei Zeilen, die 64 in Marionette sind 12,8 Zeilen.

### Was eine Note beendet

| Mechanismus | |
|---|---|
| `hold > 0` | Note klingt `hold` Ticks |
| `0F FF` | beendet sofort (`_ChannelOff`) |
| nächste Note auf derselben Spur | beendet |

Am Original bestätigt: Bei einer einzelnen Note in einem 64-Zeilen-Block kam das
Note-Off beim Neustart des Blocks, 11 ms vor dem neuen Note-On — also durch die
nächste Note, nicht durch Hold.

Umgesetzt in `MEDKit/Model/Timing.swift`.
