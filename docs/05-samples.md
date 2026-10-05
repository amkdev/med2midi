# Samples

Nur eine der acht Dateien enthält Samples: `2_ENDZEIT_NEW.OMP_WS+MU` mit 14
Stück, zusammen 107 kB. Die übrigen Songs sind reine MIDI-Songs.

## Wo die Daten liegen

`smplarr` im Modulkopf (Offset 24) zeigt auf ein Feld von Zeigern, einer je
Instrument. Null heißt: kein Sample. Dahinter ein Kopf von **6 Bytes**
(`ULONG length`, `WORD type`), dann die Daten.

**Gegengeprüft:** Der Abstand zwischen zwei aufeinanderfolgenden Sample-Zeigern
ist jedes Mal genau `length + 6` — 232382 → 240590 bei `length` 8202, und so
fort über alle vierzehn.

`type` ist bei allen 0, also gewöhnliche 8-Bit-Samples. Die Werte sind
**vorzeichenbehaftet**, −128 bis 127.

Schleifenpunkte stehen nicht beim Sample, sondern im Songkopf beim Instrument
(`rep`, `replen`, in Wörtern). Im Material des Autors sind alle vierzehn
Einzelschüsse ohne Schleife — ausnahmslos Schlagzeug.

## Warum 16-Bit-WAV

Die Vorlage hat 8 Bit, die Ausgabe 16. Das ist kein Qualitätsverlust und auch
keine Aufwertung:

- Amiga-Samples sind **vorzeichenbehaftet**, WAV mit 8 Bit ist
  **vorzeichenlos**. Eine Umrechnung braucht es in jedem Fall.
- Nach 16 Bit ist sie **exakt**: jeder Wert mal 256. Nichts geht verloren,
  nichts kommt hinzu.
- 16 Bit nimmt jeder Sampler anstandslos; bei 8 Bit gibt es Werkzeuge, die
  zicken.

Der Lo-Fi-Charakter steckt in den Daten, nicht im Behälter.

Nachgeprüft: Alle vierzehn WAV-Dateien zurückgelesen und Wert für Wert gegen
die Amiga-Bytes gehalten — keine einzige Abweichung. `afinfo` von macOS liest
sie als „1 ch, 16574 Hz, Int16".

## Abspielrate und Grundton

Ein Amiga-Sample hat keine eigene Rate. Was herauskommt, hängt von der
Paula-Periode ab, und die steht in OctaMEDs Tabelle. Entscheidend ist, wo sie
**beginnt**:

    IFNE SYNTH|IFFMOCT
        DC.W 3424,3232,…        ; nur für mehroktavige IFF-Instrumente
        DC.W 1712,1616,…
    ENDC
    per0: DC.W 856,808,762,720,678,640,604,570,538,508,480,453
          DC.W 428,404,381,360,339,320,302,285,269,254,240,226
          DC.W 214,202,190,180,170,160,151,143,135,127,120,113
          DC.W 214,202,190,…      ; ab hier wiederholt sich die Zeile
          DC.W 214,202,190,…
          DC.W 214,202,190,…

Die beiden Zeilen über `per0` werden nur bedingt assembliert. Die normale
Tabelle fängt bei `per0` an, und `856` gehört damit zu **MED-Note 1**:

| MED-Note | Name in OctaMED | Periode | Rate |
|---|---|---|---|
| 1 | `C-1` | 856 | 4 144 Hz |
| 13 | `C-2` | 428 | 8 287 Hz |
| 25 | `C-3` | 214 | **16 574 Hz** |

Geschrieben wird mit der Rate für MED-Note 25 und dem Grundton **MIDI 24**,
also `C0`.

### Am Original bestätigt — und vorher falsch

Eine erste Fassung hielt `856` für `C-3` und nannte als Grundton `C2`. Der
Autor hat das Sample in Bitwig geladen und ausprobiert: Richtig klingt es mit
`C0`. Das sind genau zwei Oktaven Unterschied — und es ist genau der Betrag,
um den die Tabelle falsch eingeordnet war.

Die Messung an der Sache schlägt das Lesen des Quelltextes. Hier hat sie ihn
berichtigt.

### Die Obergrenze

Ab der vierten Zeile wiederholt sich die Tabelle. Oberhalb von **MED-Note 36**
steigt die Tonhöhe auf dem Amiga also nicht weiter — Paula kann nicht
schneller. Im Material des Autors kommt keine Sample-Note über 36 vor, geprüft
über alle Blöcke; die Grenze spielt hier keine Rolle.

**Grundton** steht als MIDI-Notennummer **und** als Notenname. Die Nummer ist
eindeutig, der Name hängt von der Zählung ab: Mitte C (Note 60) heißt mal `C3`,
mal `C4`. Hier gilt `C3` — so zählen Bitwig von Haus aus und MIDI Monitor in
der Einstellung des Autors. Belegt an seiner Messung: eine als `C-1`
protokollierte Note trug die Nummer 12.

Die Ereignisliste benannte bis dahin nach `C4` und lag damit gegenüber seinen
Werkzeugen eine Oktave daneben — die Zahlen stimmten, nur die Namen nicht.
`MIDINote.name(_:)` ist jetzt die eine Stelle, an der das steht.

Die Nummer errechnet sich als
`49 + noteOffset + Instrumenttransponierung + Songtransponierung`. Stellt man
ihn im Sampler ein, klingt jede Note so wie auf dem Amiga — beide Skalen sind
gleichstufig, der Rest ergibt sich.

## Die Noten

Sample-Instrumente haben keinen MIDI-Kanal; der Amiga hat sie selbst erzeugt.
Der Player überging sie deshalb vollständig. Jetzt bekommen sie Noten wie jedes
andere Instrument — sie klingen nicht über MIDI, aber sie **sind** Musik.

Jedes Sample-Instrument erhält eine eigene Spur, benannt nach dem Sample mit
dem Zusatz `(Sample)`. Der Kanal ist dabei bedeutungslos und steht auf 1: Die
DAW legt je Spur ein Instrument an, und was zählt, ist die Zuordnung von Spur
zu WAV-Datei. `samples.txt` nennt sie.

Aus 13 Spuren wurden damit 24.
