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

## Geklärt: der Wertebereich von Befehl `0C` (Velocity)

Zunächst falsch umgesetzt (Verdopplung), dann gemessen und entschieden.

| Quelle | Aussage |
|---|---|
| Handbuch, `0C` (MIDI) | „The normal Amiga sample volume range of 0 - 64 is converted to the MIDI range of 0 - 127." |
| Tutka `conversion.cpp` | „MIDI volumes are in range 0-95 in OctaMED", `wert * 0x80 / 0x60` |
| **Messung an 7 Dateien** | Werte bis exakt 127, nie darüber |

**Entscheidend ist die Verteilung.** Die häufigsten Werte liegen in fast allen
Dateien auf dem 16er-Raster **16, 32, 48, 64, 80, 96, 112** — acht Stufen über
0–127. In einem 0–64-Bereich wäre das natürliche Raster 8/16/24/…/64, und 80,
96, 112 gäbe es nicht.

| Datei | ≤ 64 | häufigste Werte |
|---|---|---|
| `N_WOISTDAS_MU80.med` | 81 % | 39, 19, 31, 15, 7, 115 |
| `N_ich_will_neues.mmd1` | 92 % | 16, 32, 48, 64, 8, 96 |
| `O_Wie_Eine_Marionette.MMD` | 59 % | 64, 80, 48, 96, 32, 111 |
| `final_manchmaltriffteinlächeln2001.med` | **23 %** | 80, 96, 64, 112, 48, 32 |
| `final_soverloren.med` | **24 %** | 80, 64, 48, 96, 112, 104 |
| `sehnsuchts_blues.MMD1.pp` | 84 % | 48, 64, 80, 96, 16, 32 |
| `unsere_hände_spielen.MMD` | 84 % | 32, 48, 16, 64, 80, 96 |

Bei den beiden `final_`-Dateien liegen drei Viertel aller Velocities über 64.
Mit Skalierung würden 64, 80, 96 und 112 **alle zu 127** — beide Stücke hätten
keinerlei Dynamik mehr. Das kann nicht sein, was der Autor gehört hat.

Gegenprobe zur Vollständigkeit: Die hohen Werte stehen auf MIDI-Instrumenten,
nicht auf Sample-Instrumenten (getrennt gemessen über das auf der Spur aktive
Instrument). Und `FLAG_VOLHEX` (0x10) ist reine Anzeigesache — Dateien mit und
ohne gesetztes Flag zeigen dieselben Wertebereiche.

**Umsetzung:** durchreichen, bei 127 begrenzt
(`Befehlskatalog.velocity(ausBefehlsdaten:)`).

Davon zu trennen und ebenfalls belegt: die Instrument-Grundlautstärke `svol`
(0–64) wird verdoppelt und bei 127 gedeckelt — das zeigt das undokumentierte
Feld der 24-Byte-`InstrExt` (47→94, 49→98, 48→96, 64→127, 32→64, 50→100).
Zwei verschiedene Größen, nicht zu verwechseln.

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
