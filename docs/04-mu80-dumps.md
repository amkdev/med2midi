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
| `4C` | `10 xx xx` | 4 | 184 | **unbekannt**, nur 2 Parts |
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

Also zwei Parts aus einem Adressbereich, der sonst nicht vorkommt. Der Autor:
„man konnte da verschiedenes dumpen" — vermutlich hat er bei manchen Songs eine
andere Dump-Art gewählt.

## Offen

1. **Was ist Adressbereich `10 xx xx`?** Vier Nachrichten, zwei Parts. Im
   MU80-Handbuch (Anhang MIDI-Datenformat) nachzuschlagen.
2. **Was steht in der einen `49`-Nachricht?** MU80-eigenes Format, 21 Bytes.
3. **Die Adresstabellen selbst** — erst damit wird aus dem Dump eine lesbare
   Klangtabelle: Bank, Programm, Voice-Name, Volume, Pan, Sends, Filter,
   Hüllkurve je Part.

Für Punkt 3 braucht es den MIDI-Datenformat-Anhang des MU80-Handbuchs und die
XG-Spezifikation. Ohne die bleibt es beim Rohstrom — der aber bereits
exportiert wird und sich in das Gerät zurückspielen lässt.
