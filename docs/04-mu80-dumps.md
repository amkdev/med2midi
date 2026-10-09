# Die MU80-Dumps

Stand der Analyse. Entschlüsselt ist der Rahmen, nicht der Inhalt — das ist
Phase 3.

## Nachrichtenaufbau

Yamaha-Bulk-Dump, am Material verifiziert:

```
F0 | 43 | 0n | mm | bh bl | ah am al | <Daten> | cs | F7
     │     │    │    └─ Byteanzahl   └─ Adresse (3 Bytes)
     │     │    └─ Model-ID: 4C = XG, 49 = MU80-eigen
     │     └─ Geräte-/Kanalnummer (hier 00)
     └─ Hersteller Yamaha
```

Beispiel, erste Nachricht eines Dumps (18 Bytes):

```
f0 43 00 4c 00 07 00 00 00  00 04 00 …  40 4a f7
         └XG  └7 B  └Adr 000000
```

## Was ein Dump abdeckt

Gemessen an `N_ich_will_neues.mmd1`, Dump 0 — 408 Nachrichten, 13 154 Bytes:

| Model | Adressbereich | Nachrichten | Bytes | Bedeutung |
|---|---|---|---|---|
| `4C` | `00 xx xx` | 1 | 18 | XG System |
| `4C` | `02 xx xx` | 7 | 178 | Effekt |
| `4C` | `03 xx xx` | 2 | 46 | Effekt |
| `4C` | `08 xx xx` | 64 | 4032 | **Multi Part, alle 32 Parts** |
| `4C` | `10 xx xx` | 4 | 184 | A/D Part (Audio-Eingänge), 2 Parts |
| `4C` | `30 xx xx` | 83 | 2177 | Drum Setup 1 |
| `4C` | `31 xx xx` | 82 | 2166 | Drum Setup 2 |
| `4C` | `32 xx xx` | 82 | 2166 | Drum Setup 3 |
| `4C` | `33 xx xx` | 82 | 2166 | Drum Setup 4 |
| `49` | — | 1 | 21 | MU80-eigen |

Die 32 Parts im Bereich `08` entsprechen der Architektur des MU80 — es sind
also vollständige Speicherdumps, wie der Autor vermutete, kein Ausschnitt.

## Die Dumps sind beweisbar unbeschädigt

Eine Sollgröße für den ganzen Dump gibt es nicht und braucht es nicht: Jede
Nachricht trägt ihre Byteanzahl selbst, die Gesamtlänge folgt aus dem Inhalt.
Prüfbar ist jede Nachricht für sich — und das ist stärker als jeder Vergleich
mit einer erwarteten Größe.

Zwei Prüfungen je Nachricht:

1. **Byteanzahl**: Das Feld `bh bl` muss zur tatsächlichen Datenlänge passen
   (ohne die drei Adressbytes).
2. **Prüfsumme**: Yamahas Zweierkomplement über Byteanzahl, Adresse und Daten —
   `cs = (128 − (Summe & 0x7F)) & 0x7F`.

**Ergebnis über alle sieben Songdateien:**

| | |
|---|---|
| Dumps | 11 |
| Nachrichten | 4480 |
| Byteanzahl korrekt | **4480** |
| Prüfsumme korrekt | **4480** |
| Restbytes | **0** |

Alle Dumps sind also vollständig und unbeschädigt. Die exportierten
`.syx`-Dateien laden sauber in das Gerät.

Umgesetzt als `SysExDump.check()`; der Lader warnt, wenn eine Prüfung
fehlschlägt, und das Export-Manifest nennt das Ergebnis.

## Warum die Dumps verschieden groß sind

Zwei Größen kommen vor: **13 154 Bytes (408 Nachrichten)** und **12 970 Bytes
(404)**. Der Unterschied sind genau vier Nachrichten, alle im Bereich
`10 xx xx`:

```
10 00 00    10 00 30    10 01 00    10 01 30
```

Also zwei Parts aus einem Adressbereich, der sonst nicht vorkommt.

**Aufgelöst:** `10 00 00` ist **A/D1**, `10 01 00` ist **A/D2** — die
Audio-Eingänge des MU80, die XG wie Parts behandelt. Je Eingang zwei
Adressblöcke (`00` und `30`), macht vier Nachrichten.

Das XG-Format kennt die Bulk-Dumps einzeln: XG System, System Information,
Multi Effect 1, Multi EQ, Multi Effect 2, Multi Part, **AD Part**, Drums Setup.
Das deckt sich mit der Auskunft des Autors, am Gerät habe man verschiedenes
dumpen können — bei manchen Songs hat er den A/D-Part mitgenommen, bei anderen
nicht.

Für die Songs ist der Unterschied bedeutungslos: Die Audio-Eingänge wurden nicht
benutzt, die 184 Bytes betreffen Einstellungen für Mikrofon oder Line-Signal.

*Quelle: midi.org, „Specific Yamaha XG SYSEX". Sekundärquelle, nicht das
MU80-Handbuch — die Zuordnung passt aber exakt zu den gemessenen zwei Parts.*

## Offen

1. **Was steht in der einen `49`-Nachricht?** MU80-eigenes Format, 21 Bytes.
2. **Die Adresstabellen selbst** — erst damit wird aus dem Dump eine lesbare
   Klangtabelle: Bank, Programm, Voice-Name, Volume, Pan, Sends, Filter,
   Hüllkurve je Part.

Für Punkt 2 braucht es den MIDI-Datenformat-Anhang des MU80-Handbuchs und die
XG-Spezifikation. Ohne die bleibt es beim Rohstrom — der aber bereits
exportiert wird und sich in das Gerät zurückspielen lässt.

## Part-Belegung: was in den Dumps lesbar ist

Die Dumps folgen dem **XG-Standardschema**. Modell-ID `4C`, Adresse
`08 nn 00` für Part `nn`, danach die Parameter in fester Reihenfolge:

| Offset | Parameter | Mittelwert |
|---|---|---|
| 0 | Element Reserve | |
| 1, 2 | Bank MSB, LSB | |
| 3 | Programmnummer (0-basiert) | |
| 4 | Empfangskanal (0–15) | |
| 7 | Part Mode (0 = normal) | |
| 8 | Note Shift | `0x40` |
| 11 | Volume | |
| 14 | Pan | `0x40` |
| 18, 19, 20 | Chorus, Reverb, Variation Send | |

### Dreifach gegengeprüft

1. **Die Empfangskanäle passen zu den MED-Instrumenten.** In
   `N_ich_will_neues` haben alle 13 belegten Parts Kanäle, auf denen auch
   MED-Instrumente liegen. Wäre das Offset falsch, träfe nichts aufeinander.
2. **Note Shift und Pan stehen auf `0x40`**, dem XG-Mittelwert — genau dort,
   wo Mittenwerte stehen müssen. Die Ausnahmen sind plausibel: Part 6 hat
   `0x4C`, also +12 Halbtöne, eine Oktavschicht.
3. **Part Mode ist 0** bei allen melodischen Parts und zeigt auf den
   Schlagzeugkanälen ein Drum-Setup.

### Der eigentliche Befund: Schichtung

Mehrere Parts empfangen auf demselben MIDI-Kanal und klingen zusammen. Das
sieht man den MED-Daten **nicht** an — dort ist es ein Kanal. In
`N_ich_will_neues` liegen auf Kanal 5 drei Parts, auf den Kanälen 2, 3, 4 und
10 je zwei.

Das erklärt auch, warum die Stimmenzahl höher ist als die Notenzahl: Aus 19
gleichzeitigen Noten werden 37 Stimmen.

### Element Reserve und die Aussetzer

Die Reserven stehen bei allen Dateien auf der XG-Werkseinstellung
(6, 2, 2, …), zusammen **48 der 64 Stimmen**. Frei verteilbar bleiben 16. Ein
Part, der mehr Töne spielt als seine Reserve hergibt, bedient sich aus diesem
Rest.

Gerechnet über die Songs:

| Datei | max. Bedarf über die Reserven | Stellen über 16 |
|---|---|---|
| `N_ich_will_neues` | 22 | **51** |
| `sehnsuchts_blues` | 19 | 5 |
| übrige | 10–12 | 0 |

`N_ich_will_neues` ist genau der Song, bei dem der Autor Aussetzer hört, und
der einzige mit nennenswert vielen solchen Stellen — bei 0,9 % der Spielzeit.
Das ist ein **Modell** der XG-Stimmenverteilung, nicht am Gerät nachgemessen;
die Übereinstimmung ist aber deutlich.

### Klangnamen

`MultiPart.generalMIDINames` liefert die 128 GM-Namen. Die XG-Variante aus der
Bank ändert den Klang, behält aber den Charakter. Der genaue Name steht in der
„Sound List" des MU80 unter Bank und Programmnummer — das PDF wird dafür nicht
gebraucht, nur zum Nachschlagen im Einzelfall.

Bei Bank MSB 127 oder Part Mode ≠ 0 ist der GM-Name falsch; das sind
Drumkits mit eigener Liste.

## Nicht jeder Dump ist von Yamaha

`2_ENDZEIT_NEW.OMP_WS+MU` enthält zwei Dumps: einen für die **Korg
Wavestation** (Hersteller `0x42`, 134 609 Bytes, eine einzige Nachricht) und
einen für den MU80.

Die Prüfung war darauf nicht vorbereitet. Byteanzahl an Offset 4–5 und
Zweierkomplement vor `F7` sind **Yamahas** Schema; beim Korg stehen dort andere
Bytes. Angewendet ergab es garantiert ein Fehlurteil, und die Warnung behauptete
dann noch etwas Falsches („beginnt nicht mit F0") — der Rahmen war in Ordnung.

`Check.schemeApplies` sagt jetzt, ob geprüft werden konnte. Bei fremden
Herstellern bleibt die Rahmenprüfung, und das steht auch so da.

## Ein gekipptes Bit

In `2_ENDZEIT_NEW.OMP_WS+MU`, MU80-Dump, Nachricht **168 von 407**, Offset 6824:
dort steht `70` statt `F0`.

Es ist genau ein Bit. Der Rest der Nachricht ist unversehrt — 27 Bytes, und die
Yamaha-Prüfsumme stimmt. Damit ist auch sicher, dass `F0` dort hingehört: Eine
SysEx-Nachricht kann gar nicht anders beginnen, und der Inhalt bestätigt sich
selbst.

Über alle zwölf Yamaha-Dumps der acht Dateien ist das der **einzige** Fall.

**Folge beim Senden:** Ein Empfänger ignoriert diese Nachricht und deutet die
folgenden Bytes als Daten der vorigen — die Einstellungen eines Parts fehlen.
Der Schaden steckt in der Originaldatei, nicht im Export.

Der Test hält den Befund fest: Bricht er, ist entweder der Schaden repariert
worden oder ein neuer dazugekommen.

## Fünf gekippte Bits — am Gerät bestätigt und repariert

Der Autor hat den MU80-Dump von `2_ENDZEIT_NEW.OMP_WS+MU` an das Gerät
geschickt. Antwort: **„Check Sum Error!"**

Die Prüfung aller 407 Nachrichten fand fünf beschädigte Bytes:

| Offset | ist | soll | Art |
|---|---|---|---|
| 1717 | `00` | `40` | Datenbyte, Multi Part `08 0B 30` |
| 5224 | `F1` | `F7` | Endbyte — zwei Nachrichten hingen zusammen |
| 6824 | `70` | `F0` | Startbyte |
| 10145 | `00` | `40` | Datenbyte, Drum Setup `32 3D 00` |
| 11744 | `00` | `40` | Datenbyte, Drum Setup `33 28 00` |

### Wie jede einzelne Reparatur bewiesen ist

**Rahmenbytes** (`F0`, `F7`): Eine SysEx-Nachricht kann nicht anders beginnen
oder enden. Der Beweis liegt im Ergebnis — nach der Korrektur erfüllt die
Nachricht Byteanzahl **und** Prüfsumme, und der Dump hat 408 Nachrichten statt
407, also genau so viele wie jeder intakte Dump des Autors.

**Datenbytes:** Hier war zunächst offen, ob das Datenbyte oder das
Prüfsummenbyte beschädigt ist — von innen nicht zu unterscheiden, beide
erzeugen dieselbe Abweichung. Entschieden hat der Vergleich mit den
Geschwistern: Die vier Drum-Setups (`30`–`33`) und die 32 Parts sind parallel
aufgebaut. An jeder der drei Stellen weicht **genau ein** Byte von **allen**
Geschwistern ab, und zwar um exakt Bit 6 — es steht `00`, wo überall sonst `40`
steht. Setzt man das Bit zurück, stimmt die **gespeicherte** Prüfsumme wieder.

Damit ist auch gesagt, was nicht beschädigt war: die Prüfsummen.

### Was `SysExRepair` nicht tut

Geraten wird nichts. Eine Reparatur braucht mindestens drei Geschwister, ein
eindeutiges abweichendes Byte und eine Abweichung, welche die
Prüfsummendifferenz **exakt** erklärt. Fehlt eines davon, bleibt das Byte
stehen und die Beanstandung steht im Manifest unter „Offen".

An heilen Dumps ändert sich nichts — über alle Dateien geprüft. Dumps anderer
Hersteller bleiben unberührt, dort gilt das Schema nicht.

Die Originaldateien werden nie verändert; MEDKit hat keinen Schreibpfad auf
sie. Die Korrektur steckt nur in der exportierten `.syx`, und `dumps.txt` nennt
jedes geänderte Byte mit Offset, altem und neuem Wert und Begründung.

## Banknummern nennen die XG-Variante — am Gerät bestätigt

In `0_DIESE_WELT.OMP_WS+MU` liegen auf Kanal 4 **zwei** Parts übereinander:

| Part | Bank | Prog | GM-Name | am Gerät |
|---|---|---|---|---|
| 4 | 0/16 | 53 | Choir Aahs | **Ch.Aahs2** |
| 5 | 0/35 | 51 | SynthStrings 1 | **Syn Str3** |

Der Autor hat die rechte Spalte am MU80 abgelesen. Damit ist belegt, wie die
Angaben zusammenspielen: Der **GM-Name** nennt den Charakter, die
**Bank-LSB** die XG-Variante. Wer den genauen Namen braucht, schlägt mit
beiden Zahlen in der „Sound List" nach.

Die Spalte in `wavestation.txt` zeigte zunächst nur den **ersten**
eingerichteten Part je Kanal und verschwieg den zweiten. Aufgefallen ist das
nur, weil der Autor am Gerät nachsah. Jetzt stehen alle, mit `+` verbunden.
