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
Paula-Periode ab, und die steht in OctaMEDs Tabelle:

    per0: DC.W 856,808,762,720,678,640,604,570,538,508,480,453

`856` ist `C-3`, jede Oktave darüber halbiert. Die Rate ist Paulas PAL-Takt
geteilt durch die Periode:

| MED-Note | Periode | Rate |
|---|---|---|
| `C-3` | 856 | 4 144 Hz |
| `C-4` | 428 | 8 287 Hz |
| `C-5` | 214 | **16 574 Hz** |

Geschrieben wird mit der Rate für `C-5` und dem passenden Grundton. `C-3`
ginge auch, aber 4 kHz sieht in mancher DAW nach einem Fehler aus.

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
