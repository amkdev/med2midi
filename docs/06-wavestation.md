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

## Welcher Dump gilt?

Eine Songdatei kann mehrere Dumps tragen — `unsere_hände_spielen` hat vier,
alle für den MU80. Welcher davon beim Spielen galt, steht nirgends.

**Meistens doch.** Vier der acht Dateien schicken genau einen Dump per Befehl
`10` ab; das ist die Antwort. Und in allen vier Fällen ist es der **letzte**
seiner Art — der Autor hat ältere Fassungen behalten und die neueste
abgeschickt.

`DumpChoice` wählt deshalb so:

| Lage | Wahl | belegt? |
|---|---|---|
| ein Dump wird ausgelöst | dieser | ja |
| nur einer dieses Geräts | dieser | ja |
| mehrere, keiner ausgelöst | der letzte | **nein, Annahme** |

Die Annahme steht in `parts.txt` und `wavestation.txt` als solche da, mit dem
Hinweis auf `dumps.txt`, wo alle aufgeführt sind.

## Welches Gerät spielte welchen Kanal?

Auch das steht nirgends. Es gibt zwei Spuren, und keine ist ein Beweis:

1. **Werkszustand.** XG stellt jeden Part auf Bank 0/0, Programm 1, Lautstärke
   100, Panorama Mitte, Hall 40, Chorus 0. Steht das alles noch so, hat der
   Autor den Part nie eingerichtet — auf diesem Kanal kam der Klang von
   woanders. In `2_ENDZEIT_NEW` trifft das auf 24 der 32 Parts zu.
2. **Namensgleichheit.** Trägt das MED-Instrument den Namen einer
   Wavestation-Performance, war es die Wavestation.

`wavestation.txt` stellt beide nebeneinander:

    Kanal   MED-Instrument        MU80                      Wavestation
    7       Splash Down           Werkszustand              —
    9       Monster Entrance      Werkszustand              #17 MonsterEntrance
    11      Digilog               kein Part                 #84 Digilog
    12      Tangle                Werkszustand              #80 Tangle

Die Datei entsteht nur, wenn sie etwas zu sagen hat: wenn ein Korg-Dump
vorliegt, oder wenn ein bespielter Kanal von keinem eingerichteten MU80-Part
bedient wird. Ohne jeden Dump wissen wir nichts, dann bleibt sie weg.

**Gegenprobe:** Von den acht Dateien bekommt nur `2_ENDZEIT_NEW` eine. Bei
allen anderen ist jeder bespielte Kanal am MU80 eingerichtet — genau wie
erwartet, denn es sind reine MU80-Songs.

## Nur bespielte Kanäle

`parts.txt` listete anfangs jeden Part, der auf irgendeinem Kanal empfängt.
Der MU80 lauscht aber auf fast allen, auch wo nichts gespielt wird. Jetzt
stehen dort nur Kanäle, auf denen der Song tatsächlich Noten hat; was fehlt,
wird am Ende in einer Zeile genannt.
