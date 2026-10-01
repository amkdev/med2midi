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

**Gemessen am 2026-10-01**: OctaMED im Amiga-Emulator, MIDI-Ausgang mit
MIDI Monitor mitgelesen.

| gespeicherter Wert | gesendete Velocity |
|---|---|
| 40 | **79** |
| 64 (`$40`) | 127 |
| 65–127 (`$41`–`$7F`) | 127 |

Daraus folgt eindeutig `wert × 127 / 64`, bei 127 begrenzt:

```
40 × 127 / 64 = 79,375 → 79
64 × 127 / 64 = 127
65 × 127 / 64 = 129   → 127
```

**Damit sind alle bisherigen Annahmen widerlegt**, auch meine beiden:

| Formel | bei Wert 40 | Status |
|---|---|---|
| durchreichen | 40 | falsch |
| `× 2` | 80 | falsch (um 1 daneben) |
| Tutka `× 128/96` | 53 | falsch |
| **`× 127/64`** | **79** | **gemessen** |

Umsetzung: `Befehlskatalog.velocity(ausBefehlsdaten:)`, mit Rundung
(`(wert × 127 + 32) / 64`).

### Die Hex/Dez-Einstellung

Der Autor beobachtete, dass dieselbe Eingabe „C40" in den beiden Anzeigemodi
verschiedene Velocities ergibt — 127 im Hex-Modus, 79 im Dezimalmodus.

Das erklärt dieselbe Formel ohne Zusatzannahme: „40" bedeutet im Hex-Modus den
Wert 64, im Dezimalmodus den Wert 40. Es werden also **zwei verschiedene Bytes
gespeichert**, und beide werden gleich umgerechnet.

Offen bleibt die schärfere Frage: Ändert das Flag `FLAG_VOLHEX` (0x10 in
`flags`) die Auswertung **desselben** gespeicherten Bytes? Entscheidbar durch:
ein Pattern anlegen, nicht verändern, nur den Modus umschalten, erneut
abspielen. Bleibt die Velocity gleich, ist das Flag für den Export belanglos.

### Was das für die Songs bedeutet

Werte über 64 sättigen bei 127 — vom Autor bestätigt („41–7F = vel 127").

| Datei | Anteil > 64 | verschiedene Velocities danach |
|---|---|---|
| `final_manchmaltriffteinlächeln2001.med` | 76 % | 24 (von 42 Rohwerten) |
| `final_soverloren.med` | 75 % | **2** (von 6 Rohwerten) |
| `O_Wie_Eine_Marionette.MMD` | 40 % | 45 (von 70) |
| `N_WOISTDAS_MU80.med` | 18 % | 28 (von 58) |
| `sehnsuchts_blues.MMD1.pp` | 15 % | 46 (von 64) |
| `unsere_hände_spielen.MMD` | 15 % | 22 (von 58) |
| `N_ich_will_neues.mmd1` | 7 % | 29 (von 33) |

`final_soverloren.med` behält nur zwei verschiedene Velocities. Das ist **kein
Fehler des Exports**, sondern die Eigenschaft des Originals: OctaMED hat diese
Werte damals ebenso gesättigt. Hörbar war der Unterschied nie.

Die Diagnose meldet Werte über 64 weiterhin, damit das sichtbar bleibt.

### Nicht zu verwechseln: `svol`

Die Instrument-Grundlautstärke `svol` (0–64) wird **verdoppelt**, nicht mit
127/64 gerechnet. Das zeigt das undokumentierte Feld der 24-Byte-`InstrExt`:
47→94, 49→98, 48→96, 64→127, 32→64, 50→100. Mit `× 127/64` ergäbe 47 den Wert
93, gemessen ist 94. Zwei verschiedene Größen mit zwei verschiedenen Formeln.

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
