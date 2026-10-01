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
            if let g = defaultVolumeSetting(ausBefehlsdaten: b.data) {
                return "Grundlautstärke des Instruments auf \(g) setzen"
            }
            return "Velocity \(velocity(ausBefehlsdaten: b.data, lesart: .sevenBit)) "
                 + "(7 Bit) · \(velocity(ausBefehlsdaten: b.data, lesart: .hexadecimal)) (hex) "
                 + "· \(velocity(ausBefehlsdaten: b.data, lesart: .decimal)) (dezimal)"
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

    /// Velocity aus dem Datenbyte des Befehls `0C`.
    ///
    /// **Am Original gemessen** (Amiga-Emulator, MIDI-Ausgang mit MIDI Monitor,
    /// 2026-10-01): *dieselben* Patterndaten, nur der Anzeigemodus
    /// umgeschaltet — Byte `0x40` ergibt im Hex-Modus 127, im Dezimalmodus 79.
    /// Der Modus wird also beim Abspielen ausgewertet, nicht nur bei der
    /// Anzeige.
    ///
    /// Umrechnung in beiden skalierten Fällen:
    ///
    ///     velocity = min(⌊wert × 127 / 64⌋, 127)
    ///
    /// Ganzzahlig abgeschnitten ist das identisch mit „verdoppeln, von null
    /// gezählt" (`2v − 1` für `v = 1…64`), weil `v × 127/64 = 2v − v/64`.
    /// Beide Beschreibungen meinen dieselbe Funktion. Abschneiden, nicht
    /// runden: mit Rundung käme bei `v = 32` fälschlich 64 statt 63 heraus.
    ///
    /// Im Fall `.sevenBit` wird **nicht** skaliert — der Wert ist bereits die
    /// Velocity. Quelle: OpenMPT `Load_med.cpp`, Befehl 0x0C, dritte
    /// Verzweigung (`(param & 0x7F + 1) / 2` rechnet dort auf die interne
    /// 0–64-Skala herunter).
    ///
    /// Werte ab `0x80` setzen laut Handbuch die Grundlautstärke des
    /// Instruments (`$80`–`$C0` für 0–64) statt die Notenlautstärke. In den
    /// sieben Testdateien kommt das in über 11 000 `0C`-Befehlen **kein
    /// einziges Mal** vor; die Diagnose meldet es, falls doch.
    public static func velocity(ausBefehlsdaten byte: UInt8,
                                lesart: VolumeEncoding) -> UInt8 {
        if byte >= 0x80 { return 0 }   // setzt die Grundlautstärke, keine Note
        switch lesart {
        case .sevenBit:
            return byte & 0x7F
        case .hexadecimal:
            return UInt8(min(min(Int(byte), 64) * 127 / 64, 127))
        case .decimal:
            let value = Int(byte >> 4) * 10 + Int(byte & 0x0F)
            return UInt8(min(value * 127 / 64, 127))
        }
    }

    /// Grundlautstärke, die ein `0C`-Wert ab `0x80` setzt (0–64), sonst `nil`.
    public static func defaultVolumeSetting(ausBefehlsdaten byte: UInt8) -> UInt8? {
        byte >= 0x80 ? min(byte - 0x80, 64) : nil
    }

    /// Instrument-Grundlautstärke `svol` (0–64) in den MIDI-Bereich.
    ///
    /// Dies ist **belegt**, anders als die Velocity oben: Das undokumentierte
    /// Feld der 24-Byte-`InstrExt` enthält genau diesen Wert, und der Vergleich
    /// ergab `svol × 2`, gedeckelt bei 127 — 47→94, 49→98, 48→96, 64→127,
    /// 32→64, 50→100. Alle sechs Messwerte passen.
    public static func midiVolume(ausSvol svol: UInt8) -> UInt8 {
        UInt8(min(Int(svol) * 2, 127))
    }
}
