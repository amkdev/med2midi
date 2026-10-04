import Foundation

/// Ein Befehl aus einer Pattern-Zelle: Nummer plus Datenbyte.
///
/// Ab MMD1 ist die Nummer ein volles Byte (0x00–0xFF); in MMD0 nur 4 Bit.
public struct Command: Equatable, Hashable, Sendable {
    public let number: UInt8
    public let data: UInt8

    public init(number: UInt8, data: UInt8) {
        self.number = number
        self.data = data
    }

    /// Eine Zelle ohne Befehl. Achtung: Befehl `00` mit Datenbyte ≠ 0 ist ein
    /// echter Befehl (MIDI-Controller-Wert) und darf nicht als leer gelten.
    public var isEmpty: Bool { number == 0 && data == 0 }

    public var hex: String {
        String(format: "%02X%02X", number, data)
    }
}

/// Was ein Befehl auf MIDI-Ebene bewirkt.
///
/// Maßgebliche Quelle: OctaMED-SoundStudio-Handbuch, Anhang A
/// <https://retro.pasz.nl/resources/octamed-soundstudio-manual/appendices/app-a/>
///
/// Wichtig: Befehle bedeuten für Sample-Instrumente etwas anderes als für
/// MIDI-Instrumente. Dieses Projekt wertet ausschließlich die MIDI-Seite aus.
/// Tutkas `conversion.cpp` ist an fünf Stellen falsch (05, 0A, 16, 17, 1C) —
/// siehe docs/02-befehlskatalog.md.
public enum MIDIEffect: Equatable, Sendable {
    case controllerValue                  // 00 — Wert für die mit 05 gewählte Nummer
    case pitchBendUp                    // 01
    case pitchBendDown                     // 02
    case setPitchBend                 // 03, 13
    case modulationWheel                  // 04 -> CC1
    case controllerNumber                // 05
    case playSequenceJump                   // 0B
    case setHold                      // 08 (Decay gibt es bei MIDI nicht)
    case ticksPerRow                   // 09
    case polyphonicAftertouch            // 0A
    case velocity                        // 0C
    case channelAftertouch                 // 0D
    case pan                             // 0E -> CC10
    case tempoOrSpecial             // 0F
    case sendSysEx                     // 10
    case volumeController            // 17 -> CC7
    case repeatRows                // 16
    case midiPreset                      // 1C
    case jumpToNextSequence            // 1D
    case repeatRow                // 1E
    case delayOrRetrigger          // 1F
    case assignableController(index: Int)    // 31–3F, Nummer aus MMDMIDICmd3x
    case noEffectOnMIDI              // 15, 18, 19, 1A, 1B
    case unknown
}

/// Sonderwerte des Befehls `0F`. Quelle: Anhang A, "Command 0F".
public enum TempoSpecial: Equatable, Sendable {
    case retriggerTwice        // F1
    case delayHalfRow     // F2
    case retriggerThreeTimes        // F3
    case delayOneThirdRow     // F4
    case delayTwoThirdsRow    // F5
    case waitUntilSent       // F7
    case holdPedalOn             // FA
    case holdPedalOff            // FB
    case stopSong            // FE
    case stopNote             // FF
    case setTempo(UInt8)

    public init(data: UInt8) {
        switch data {
        case 0xF1: self = .retriggerTwice
        case 0xF2: self = .delayHalfRow
        case 0xF3: self = .retriggerThreeTimes
        case 0xF4: self = .delayOneThirdRow
        case 0xF5: self = .delayTwoThirdsRow
        case 0xF7: self = .waitUntilSent
        case 0xFA: self = .holdPedalOn
        case 0xFB: self = .holdPedalOff
        case 0xFE: self = .stopSong
        case 0xFF: self = .stopNote
        default:   self = .setTempo(data)
        }
    }
}

public enum CommandCatalog {
    /// MIDI-Bedeutung einer Befehlsnummer.
    public static func midiEffect(_ number: UInt8) -> MIDIEffect {
        switch number {
        case 0x00: return .controllerValue
        case 0x01: return .pitchBendUp
        case 0x02: return .pitchBendDown
        case 0x03, 0x13: return .setPitchBend
        case 0x04: return .modulationWheel
        case 0x05: return .controllerNumber
        case 0x08: return .setHold
        case 0x09: return .ticksPerRow
        case 0x0A: return .polyphonicAftertouch
        case 0x0B: return .playSequenceJump
        case 0x0C: return .velocity
        case 0x0D: return .channelAftertouch
        case 0x0E: return .pan
        case 0x0F: return .tempoOrSpecial
        case 0x10: return .sendSysEx
        case 0x15, 0x18, 0x19, 0x1A, 0x1B: return .noEffectOnMIDI
        case 0x16: return .repeatRows
        case 0x17: return .volumeController
        case 0x1C: return .midiPreset
        case 0x1D: return .jumpToNextSequence
        case 0x1E: return .repeatRow
        case 0x1F: return .delayOrRetrigger
        case 0x31...0x3F: return .assignableController(index: Int(number - 0x31))
        default: return .unknown
        }
    }

    /// Kurze Erklärung für die Pattern-Ansicht (Mouseover).
    public static func explanation(_ b: Command) -> String {
        switch midiEffect(b.number) {
        case .controllerValue:
            // Handbuch: "If you need to use a controller value of $00 … use level 80."
            let value = b.data == 0x80 ? 0 : Int(b.data)
            return "Controller-Wert \(value) (Nummer zuvor mit 05 gesetzt)"
        case .controllerNumber:
            return "Controller-Nummer auf CC\(b.data) setzen"
        case .velocity:
            func beschreibe(_ e: VolumeEncoding) -> String {
                switch volumeCommand(data: b.data, encoding: e) {
                case .velocity(let v):          return "\(v)"
                case .setDefaultVolume(let v):  return "Grundlautstärke \(v)"
                case .ignored:                  return "ohne Wirkung"
                }
            }
            if case .setDefaultVolume(let v) = volumeCommand(data: b.data, encoding: .hexadecimal) {
                return "Grundlautstärke des Instruments auf \(v) setzen und damit spielen"
            }
            return "Velocity — 7 Bit: \(beschreibe(.sevenBit)) · "
                 + "hex: \(beschreibe(.hexadecimal)) · dezimal: \(beschreibe(.decimal))"
        case .volumeController:
            return "Lautstärke CC7 = \(b.data)"
        case .pan:
            return "Pan CC10 = \(b.data)"
        case .modulationWheel:
            return "Modulation CC1 = \(b.data)"
        case .setHold:
            return "Hold = \(b.data)"
        case .ticksPerRow:
            return "Ticks pro Zeile = \(b.data)"
        case .polyphonicAftertouch:
            return "Polyphoner Aftertouch \(b.data)"
        case .channelAftertouch:
            return "Kanal-Aftertouch \(b.data)"
        case .pitchBendUp:   return "Pitchbend aufwärts, \(Int(b.data) * 8) Schritte je Tick"
        case .pitchBendDown:    return "Pitchbend abwärts, \(Int(b.data) * 8) Schritte je Tick"
        case .setPitchBend: return "Pitchbend auf \(Int8(bitPattern: b.data))"
        case .sendSysEx:    return "SysEx-Dump Nr. \(b.data) senden"
        case .midiPreset:     return "MIDI-Preset \(b.data)"
        case .repeatRows: return "Blockabschnitt wiederholen (\(b.data))"
        case .jumpToNextSequence: return "Sprung zur nächsten Sequenz, Zeile \(b.data)"
        case .repeatRow: return "Zeile \(b.data)-mal wiederholen"
        case .playSequenceJump:  return "Sprung zu Playseq-Position \(b.data)"
        case .delayOrRetrigger:
            return b.data > 15 ? "Note um \(b.data >> 4) Ticks verzögern"
                                : "Note \(b.data)-fach retriggern"
        case .assignableController(let i):
            return "Freier Controller #\(i + 1) = \(b.data) (Nummer aus Cmd3x-Tabelle)"
        case .tempoOrSpecial:
            switch TempoSpecial(data: b.data) {
            case .stopNote:          return "Note auf dieser Spur stoppen"
            case .stopSong:         return "Song anhalten"
            case .retriggerTwice:     return "Note zweimal spielen"
            case .retriggerThreeTimes:     return "Note dreimal spielen"
            case .delayHalfRow:  return "Note um halbe Zeile verzögern"
            case .delayOneThirdRow:  return "Note um ein Drittel Zeile verzögern"
            case .delayTwoThirdsRow: return "Note um zwei Drittel Zeile verzögern"
            case .waitUntilSent:    return "Warten, bis Nachrichten gesendet sind"
            case .holdPedalOn:          return "Hold-Pedal an"
            case .holdPedalOff:         return "Hold-Pedal aus"
            case .setTempo(let t):   return "Tempo = \(t)"
            }
        case .noEffectOnMIDI:
            return "ohne Wirkung bei MIDI-Instrumenten"
        case .unknown:
            return "unbekannter Befehl"
        }
    }

    /// Wie das Datenbyte von Befehl `0C` zu lesen ist.
    ///
    /// OctaMED kennt drei Fälle. Welcher gilt, hängt von `FLAG_VOLHEX` und
    /// davon ab, ob der Block eine Befehlserweiterung trägt.
    public enum VolumeEncoding: Sendable, Equatable {
        /// Block hat eine Befehlserweiterung (`cmdExtTableOffset`): das Byte
        /// ist bereits der 7-Bit-Wert 0–127, also direkt MIDI-Velocity.
        case sevenBit
        /// `FLAG_VOLHEX` gesetzt: das Byte ist ein Hexwert 0–64.
        case hexadecimal
        /// `FLAG_VOLHEX` nicht gesetzt: die beiden Halbbytes sind
        /// Dezimalziffern, `0x40` bedeutet also 40.
        case decimal
    }

    /// Was ein `0C`-Befehl bewirkt.
    ///
    /// Die Playroutine kennt drei Ausgänge, nicht einen. Quelle:
    /// `MED_PlayRoutine.i`, Marke `.f_0c`, bestätigt durch Messung am Original.
    public enum VolumeCommand: Equatable, Sendable {
        /// Neue Velocity für die Spur.
        case velocity(UInt8)
        /// Wert ab `0x80`: setzt die Grundlautstärke des Instruments (0–64)
        /// **und** spielt die Note damit.
        case setDefaultVolume(UInt8)
        /// Ausserhalb des gültigen Bereichs — der Befehl tut nichts. Die
        /// zuletzt gesetzte Lautstärke der Spur bleibt stehen, bei einer
        /// frischen Note also die Grundlautstärke des Instruments.
        case ignored
    }

    /// Wirkung des Befehls `0C`.
    ///
    /// **Am Original gemessen** (Amiga-Emulator, MIDI Monitor, 2026-10-01):
    ///
    /// | Datenbyte | Wirkung |
    /// |---|---|
    /// | `0x00`–`0x40` | Velocity, skaliert |
    /// | `0x41`–`0x7F` | **nichts** — es gilt weiter die Grundlautstärke |
    /// | `0x80`–`0xC0` | setzt die Grundlautstärke und spielt damit |
    ///
    /// Das deckt sich mit dem Assembler der Playroutine:
    ///
    /// ```asm
    /// .volhex:
    ///     CMP.B   #64,D0
    ///     BHI.S   .go_nocmd      ; über 64: Befehl verwerfen
    /// .plr_setvol:
    ///     MOVE.B  D0,trk_prevvol(A5)
    /// ```
    ///
    /// Der Zweig steht dort in einem `IFNE CHECK`, und KONEYs Demo-Fassung
    /// setzt `CHECK EQU 0`. Im echten OctaMED ist er aktiv — die Messung
    /// entscheidet gegen den abgeschalteten Code.
    ///
    /// **Ausnahme `.sevenBit`:** Trägt der Block eine Befehlserweiterung, ist
    /// der Wert bereits 0–127 und wird weder skaliert noch bei 64 begrenzt.
    /// Sonst wären in den MMD3-Dateien drei Viertel aller `0C`-Befehle
    /// wirkungslos. Quelle: OpenMPT `Load_med.cpp`, dritte Verzweigung.
    public static func volumeCommand(data byte: UInt8,
                                     encoding: VolumeEncoding) -> VolumeCommand {
        // Bit 7 wird zuerst geprüft, vor der Lesart — wie im Assembler (BPL).
        if byte >= 0x80 {
            let v = byte & 0x7F
            return v <= 64 ? .setDefaultVolume(v) : .ignored
        }
        switch encoding {
        case .sevenBit:
            return .velocity(byte & 0x7F)
        case .hexadecimal:
            return byte <= 64 ? .velocity(scale(byte)) : .ignored
        case .decimal:
            let v = Int(byte >> 4) * 10 + Int(byte & 0x0F)
            return v <= 64 ? .velocity(scale(UInt8(v))) : .ignored
        }
    }

    /// 0–64 auf die MIDI-Velocity. Abgeschnitten, nicht gerundet:
    /// `⌊v × 127/64⌋ == 2v − 1` für `v = 1…64` — Verdopplung mit Nullbasis.
    private static func scale(_ v: UInt8) -> UInt8 {
        UInt8(min(Int(v) * 127 / 64, 127))
    }

    /// Instrument-Grundlautstärke `svol` (0–64) in den MIDI-Bereich.
    ///
    /// Dieselbe Skalierung wie beim Befehl `0C`, und aus demselben Grund: Die
    /// Abspielroutine kennt nur **eine** Lautstärke je Spur. Jede Zelle mit
    /// Instrumentnummer setzt sie auf `inst_svol`
    ///
    ///     MOVE.B inst_svol(A0),trk_prevvol(A5)  ;vol of this instr
    ///
    /// und `0C` überschreibt dasselbe Feld. Was danach als Velocity
    /// hinausgeht, durchläuft denselben Weg — eine zweite Formel kann es
    /// nicht geben.
    ///
    /// Maßgeblich ist die Messung am MIDI-Ausgang: `C40` in Hex-Anzeige
    /// (Wert 64) ergab 127, in Dezimalanzeige (Wert 40) ergab 79. Das ist
    /// `⌊v × 127/64⌋`, nicht `v × 2` — Letzteres ergäbe 80.
    ///
    /// Das undokumentierte Feld der 24-Byte-`InstrExt` enthält `svol × 2`
    /// (gemessen: 47→94, 49→98, 48→96, 64→127, 32→64, 50→100). Das belegt
    /// aber nur, was in der **Datei** steht, nicht was gesendet wird; die
    /// beiden Formeln unterscheiden sich ohnehin nur um eins.
    public static func midiVolume(ausSvol svol: UInt8) -> UInt8 {
        scale(min(svol, 64))
    }
}
