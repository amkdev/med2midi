# Testpattern für den Emulator

Klärt drei offene Fragen in einem Durchgang. Aufbau in OctaMED, MIDI-Ausgang
mit **MIDI Monitor** (Mac) mitlesen.

## Vorbereitung

- **Instrument 1**: MIDI-Kanal 1, `Hold = 0`, `Decay = 0`
- **Instrument 2**: MIDI-Kanal 2, `Hold = 6`, `Decay = 0`
- Tempo notieren: BPM-Modus an/aus, Ticks pro Zeile (TPL), Zeilen pro Beat.
  Steht in der Informationszeile, z. B. „Tempo = BPM 66/5".
- Ein leerer Block mit mindestens 40 Zeilen, zwei Spuren.

## Das Pattern

| Zeile | Spur 0 | Spur 1 | prüft |
|---|---|---|---|
| 000 | `C-4 1 0C40` | | Velocity bei `$40` |
| 004 | `--- 1 0FFF` | | |
| 008 | `C-4 1 0C20` | | Velocity bei `$20` |
| 012 | `--- 1 0FFF` | | |
| 016 | `C-4 1 0C7F` | | Velocity bei `$7F` |
| 020 | `--- 1 0FFF` | | |
| 024 | | `C-4 2 0000` | Hold-Einheit |
| 032 | `C-4 1 0FFF` | | Note **und** Note-Off in einer Zelle |

## Was abzulesen ist

### 1. Velocity — die Hauptfrage

| `0C40` sendet | Bedeutung |
|---|---|
| **127** | 0–64 wird auf 0–127 skaliert. Bestätigt Handbuch und Autor. |
| **64** | Der Wert wird durchgereicht. Bestätigt die Messung an den Songdateien. |

Gegenprobe mit `0C20` (→ 64 bzw. 32) und `0C7F` (→ 127 in beiden Fällen).
Der Fall `0C7F` ist zusätzlich interessant: Kommt dort überhaupt etwas, oder
weist OctaMED den Wert ab?

Hintergrund in `02-befehlskatalog.md`. Umschalter im Code:
`Befehlskatalog.velocity(ausBefehlsdaten:abbildung:)`.

### 2. Hold-Einheit

Instrument 2 hat `Hold = 6`. Im MIDI Monitor den Abstand zwischen Note-On und
Note-Off messen und mit der Zeilendauer vergleichen.

- Note-Off nach **einer Zeile** (bei TPL 6) → Hold zählt **Ticks**.
- Note-Off nach **sechs Zeilen** → Hold zählt **Zeilen**.

Die Sekundärquelle sagt Ticks; bestätigt ist es nicht.

### 3. Note und `0F FF` in derselben Zelle

Zeile 032 trägt beides. Im MIDI Monitor die Reihenfolge ablesen:

- `Note Off` vor `Note On` → alte Note wird zuerst beendet, die neue erklingt.
- `Note On` vor `Note Off` → die neue Note wird sofort wieder abgewürgt.

Kommt in den echten Dateien vor, z. B. `final_soverloren.med`, Block 27,
Zeile 0, Spur 6 (`D-4 6 0FFF`).

## Falls noch Zeit ist

- **Befehl `0x17`**: eine Zeile `--- 1 1740` — kommt `CC 7` mit Wert 64 oder
  mit 127? Das prüft, ob `17` ebenfalls skaliert oder durchreicht.
- **Befehl `0x05`/`0x00`**: `--- 1 054A` gefolgt von `--- 1 0040` — kommt
  `CC 74` mit Wert 64?
- **Instrumentnummer ohne Note**: In eine Spur eine Note mit Instrument 1
  setzen, darunter eine Zelle mit *nur* Instrument 2 (Kanal 2), darunter
  `--- 1740`. Geht `CC 7` an Kanal 1 oder Kanal 2? Das klärt, ob eine
  Instrumentzelle ohne Note den Kanalbezug schon verschiebt.
- **Löschverhalten**: Eine Note mit Instrument setzen, dann nur die Note
  löschen — bleibt die Instrumentnummer stehen? Das würde die tausenden
  Zellen erklären (siehe `02-befehlskatalog.md`).
