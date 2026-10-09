# Korg Wavestation

`2_ENDZEIT_NEW.OMP_WS+MU` enthält neben dem MU80-Dump einen zweiten: 134 609
Bytes für eine **Korg Wavestation**, als eine einzige SysEx-Nachricht.

    F0 42 30 28 50 …

`42` ist Korg, `30` Format 3 mit Kanal 0, `28` das Modell Wavestation, `50`
die Funktion.

## Die Verpackung — gemessen, nicht angenommen

Korg packt in vielen Geräten acht MIDI-Bytes zu sieben Datenbytes. **Hier
nicht.** Von 134 602 Nutzbytes liegt genau eines über 15, und das ist das
Prüfbyte am Ende. Es sind also **Nibbles**: zwei MIDI-Bytes je Datenbyte.

Die 7-Bit-Entpackung ergab null Textstellen. Die Nibble-Entpackung ergibt 233 —
aber nur in einer Reihenfolge:

| Kopflänge | Reihenfolge | Textstellen | Beispiel |
|---|---|---|---|
| 5 | **niederwertig zuerst** | **233** | `Dark Village` |
| 5 | höherwertig zuerst | 15 | `5G'VVG` |
| 6 | höherwertig zuerst | 235 | `Ab{ovYllageo` |

Die 235 bei Kopflänge 6 sehen auf den ersten Blick besser aus, sind es aber
nicht: Jedes Zeichen ist um ein halbes Byte verschoben, und aus
`Dark Village` wird `Ab{ovYllageo`. Die Zahl allein hätte in die Irre geführt;
entschieden hat der Blick auf den Text.

`0x7F` ist das Leerzeichen des Geräts.

## Die Struktur

Namensfelder sind 16 Bytes: 15 Zeichen, dann `0x00`. Sie stehen in zwei
Blöcken mit festem Abstand:

| Block | ab Offset | Abstand | Anzahl |
|---|---|---|---|
| Performances | 1 813 | 181 | **100** |
| Patches | 19 913 | 426 | **70** |

Gesucht werden die Blöcke zur Laufzeit, nicht über feste Offsets — die Zahlen
stammen aus **einem** Dump.

**Die Gegenprobe:** Die Wavestation führt 50 Performances und 35 Patches je
Bank. 100 und 70 sind genau zwei volle RAM-Bänke. Dass beide Zahlen aufgehen,
ist der Beleg, dass die Blockgrenzen stimmen.

Zwei Feinheiten waren dafür nötig:

- **Namenlose Speicherplätze zählen mit.** Zwischen Patch 49 und 51 liegt ein
  nie benannter Platz. Ließe man ihn aus, verschöbe sich die Nummerierung
  aller folgenden Klänge.
- **Die Blöcke dürfen sich nicht überlappen.** Die Rückwärtssuche des
  Patch-Blocks reichte einen Platz in den Performance-Block hinein, sodass
  `Destructo` zweimal zählte — als 101. Performance und als 1. Patch. Erst
  abgeschnitten ergeben sich 100 und 70.

## Wozu das gut ist

Der Autor hat seine MED-Instrumente nach den gewählten Klängen benannt.
`wavestation.txt` macht daraus eine belegte Verbindung:

    Instr  1  Kanal  1  Wavelight        Performance #70 „Wavelight“
    Instr  3  Kanal  3  Paralandrax      Performance #7 „Paralandrax“
    Instr  4  Kanal  4  Legend           Performance #27 „Legend changed“  (ähnlich)
    Instr  7  Kanal  7  Splash Down      nicht im Dump

Neun von elf Namen finden sich wieder. `Splash Down` und `Fragments` nicht —
der Dump hält die RAM-Bänke, Klänge aus dem ROM oder von einer Karte stehen
nicht darin.

## Und der MU80 in derselben Datei?

Von 32 Parts sind **24 im Werkszustand** (Bank 0/0, Programm 1, Volume 100,
Reverb 40). Nur acht sind angepasst. Dieser Song ist im Kern ein
Wavestation-Song; der MU80 kam später dazu.

Die Kanalbelegung hilft bei der Zuordnung nicht: Der MU80 empfängt auf 15 von
16 Kanälen, auch dort, wo er nichts Eigenes spielt. Der Namensabgleich ist das
verlässlichere Mittel.
