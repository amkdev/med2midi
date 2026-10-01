import Foundation

/// Ein Befehl aus einer Pattern-Zelle: Nummer plus Datenbyte.
///
/// Ab MMD1 ist die Nummer ein volles Byte (0x00–0xFF); in MMD0 nur 4 Bit.
public struct Befehl: Equatable, Hashable, Sendable {
    public let nummer: UInt8
    public let daten: UInt8

    public init(nummer: UInt8, daten: UInt8) {
        self.nummer = nummer
        self.daten = daten
    }

    /// Eine Zelle ohne Befehl. Achtung: Befehl `00` mit Datenbyte ≠ 0 ist ein
    /// echter Befehl (MIDI-Controller-Wert) und darf nicht als leer gelten.
    public var istLeer: Bool { nummer == 0 && daten == 0 }

    public var hex: String {
        String(format: "%02X%02X", nummer, daten)
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
public enum MIDIWirkung: Equatable, Sendable {
    case controllerWert                  // 00 — Wert für die mit 05 gewählte Nummer
    case pitchbendAuf                    // 01
    case pitchbendAb                     // 02
    case pitchbendSetzen                 // 03, 13
    case modulationsrad                  // 04 -> CC1
    case controllerNummer                // 05
    case playseqSprung                   // 0B
    case holdSetzen                      // 08 (Decay gibt es bei MIDI nicht)
    case ticksProZeile                   // 09
    case polyphonerAftertouch            // 0A
    case velocity                        // 0C
    case kanalAftertouch                 // 0D
    case pan                             // 0E -> CC10
    case tempoOderSonderfall             // 0F
    case sysexSenden                     // 10
    case lautstärkeController            // 17 -> CC7
    case blockWiederholen                // 16
    case midiPreset                      // 1C
    case sprungNächsteSequenz            // 1D
    case zeileWiederholen                // 1E
    case verzögernOderRetrigger          // 1F
    case freierController(index: Int)    // 31–3F, Nummer aus MMDMIDICmd3x
    case ohneWirkungBeiMIDI              // 15, 18, 19, 1A, 1B
    case unbekannt
}

/// Sonderwerte des Befehls `0F`. Quelle: Anhang A, "Command 0F".
public enum TempoSonderfall: Equatable, Sendable {
    case retriggerZweimal        // F1
    case verzögernHalbeZeile     // F2
    case retriggerDreimal        // F3
    case verzögernEinDrittel     // F4
    case verzögernZweiDrittel    // F5
    case wartenBisGesendet       // F7
    case holdPedalAn             // FA
    case holdPedalAus            // FB
    case songAnhalten            // FE
    case noteStoppen             // FF
    case tempoSetzen(UInt8)

    public init(daten: UInt8) {
        switch daten {
        case 0xF1: self = .retriggerZweimal
        case 0xF2: self = .verzögernHalbeZeile
        case 0xF3: self = .retriggerDreimal
        case 0xF4: self = .verzögernEinDrittel
        case 0xF5: self = .verzögernZweiDrittel
        case 0xF7: self = .wartenBisGesendet
        case 0xFA: self = .holdPedalAn
        case 0xFB: self = .holdPedalAus
        case 0xFE: self = .songAnhalten
        case 0xFF: self = .noteStoppen
        default:   self = .tempoSetzen(daten)
        }
    }
}

public enum Befehlskatalog {
    /// MIDI-Bedeutung einer Befehlsnummer.
    public static func midiWirkung(_ nummer: UInt8) -> MIDIWirkung {
        switch nummer {
        case 0x00: return .controllerWert
        case 0x01: return .pitchbendAuf
        case 0x02: return .pitchbendAb
        case 0x03, 0x13: return .pitchbendSetzen
        case 0x04: return .modulationsrad
        case 0x05: return .controllerNummer
        case 0x08: return .holdSetzen
        case 0x09: return .ticksProZeile
        case 0x0A: return .polyphonerAftertouch
        case 0x0B: return .playseqSprung
        case 0x0C: return .velocity
        case 0x0D: return .kanalAftertouch
        case 0x0E: return .pan
        case 0x0F: return .tempoOderSonderfall
        case 0x10: return .sysexSenden
        case 0x15, 0x18, 0x19, 0x1A, 0x1B: return .ohneWirkungBeiMIDI
        case 0x16: return .blockWiederholen
        case 0x17: return .lautstärkeController
        case 0x1C: return .midiPreset
        case 0x1D: return .sprungNächsteSequenz
        case 0x1E: return .zeileWiederholen
        case 0x1F: return .verzögernOderRetrigger
        case 0x31...0x3F: return .freierController(index: Int(nummer - 0x31))
        default: return .unbekannt
        }
    }

    /// Kurze Erklärung für die Pattern-Ansicht (Mouseover).
    public static func erklärung(_ b: Befehl) -> String {
        switch midiWirkung(b.nummer) {
        case .controllerWert:
            // Handbuch: "If you need to use a controller value of $00 … use level 80."
            let wert = b.daten == 0x80 ? 0 : Int(b.daten)
            return "Controller-Wert \(wert) (Nummer zuvor mit 05 gesetzt)"
        case .controllerNummer:
            return "Controller-Nummer auf CC\(b.daten) setzen"
        case .velocity:
            if let g = grundlautstärke(ausBefehlsdaten: b.daten) {
                return "Grundlautstärke des Instruments auf \(g) setzen"
            }
            return "Velocity \(velocity(ausBefehlsdaten: b.daten, lesart: .siebenBit)) "
                 + "(7 Bit) · \(velocity(ausBefehlsdaten: b.daten, lesart: .hexadezimal)) (hex) "
                 + "· \(velocity(ausBefehlsdaten: b.daten, lesart: .dezimal)) (dezimal)"
        case .lautstärkeController:
            return "Lautstärke CC7 = \(b.daten)"
        case .pan:
            return "Pan CC10 = \(b.daten)"
        case .modulationsrad:
            return "Modulation CC1 = \(b.daten)"
        case .holdSetzen:
            return "Hold = \(b.daten)"
        case .ticksProZeile:
            return "Ticks pro Zeile = \(b.daten)"
        case .polyphonerAftertouch:
            return "Polyphoner Aftertouch \(b.daten)"
        case .kanalAftertouch:
            return "Kanal-Aftertouch \(b.daten)"
        case .pitchbendAuf:   return "Pitchbend aufwärts, \(Int(b.daten) * 8) Schritte je Tick"
        case .pitchbendAb:    return "Pitchbend abwärts, \(Int(b.daten) * 8) Schritte je Tick"
        case .pitchbendSetzen: return "Pitchbend auf \(Int8(bitPattern: b.daten))"
        case .sysexSenden:    return "SysEx-Dump Nr. \(b.daten) senden"
        case .midiPreset:     return "MIDI-Preset \(b.daten)"
        case .blockWiederholen: return "Blockabschnitt wiederholen (\(b.daten))"
        case .sprungNächsteSequenz: return "Sprung zur nächsten Sequenz, Zeile \(b.daten)"
        case .zeileWiederholen: return "Zeile \(b.daten)-mal wiederholen"
        case .playseqSprung:  return "Sprung zu Playseq-Position \(b.daten)"
        case .verzögernOderRetrigger:
            return b.daten > 15 ? "Note um \(b.daten >> 4) Ticks verzögern"
                                : "Note \(b.daten)-fach retriggern"
        case .freierController(let i):
            return "Freier Controller #\(i + 1) = \(b.daten) (Nummer aus Cmd3x-Tabelle)"
        case .tempoOderSonderfall:
            switch TempoSonderfall(daten: b.daten) {
            case .noteStoppen:          return "Note auf dieser Spur stoppen"
            case .songAnhalten:         return "Song anhalten"
            case .retriggerZweimal:     return "Note zweimal spielen"
            case .retriggerDreimal:     return "Note dreimal spielen"
            case .verzögernHalbeZeile:  return "Note um halbe Zeile verzögern"
            case .verzögernEinDrittel:  return "Note um ein Drittel Zeile verzögern"
            case .verzögernZweiDrittel: return "Note um zwei Drittel Zeile verzögern"
            case .wartenBisGesendet:    return "Warten, bis Nachrichten gesendet sind"
            case .holdPedalAn:          return "Hold-Pedal an"
            case .holdPedalAus:         return "Hold-Pedal aus"
            case .tempoSetzen(let t):   return "Tempo = \(t)"
            }
        case .ohneWirkungBeiMIDI:
            return "ohne Wirkung bei MIDI-Instrumenten"
        case .unbekannt:
            return "unbekannter Befehl"
        }
    }

    /// Wie das Datenbyte von Befehl `0C` zu lesen ist.
    ///
    /// OctaMED kennt drei Fälle. Welcher gilt, hängt von `FLAG_VOLHEX` und
    /// davon ab, ob der Block eine Befehlserweiterung trägt.
    public enum Lautstärkelesart: Sendable, Equatable {
        /// Block hat eine Befehlserweiterung (`cmdExtTableOffset`): das Byte
        /// ist bereits der 7-Bit-Wert 0–127, also direkt MIDI-Velocity.
        case siebenBit
        /// `FLAG_VOLHEX` gesetzt: das Byte ist ein Hexwert 0–64.
        case hexadezimal
        /// `FLAG_VOLHEX` nicht gesetzt: die beiden Halbbytes sind
        /// Dezimalziffern, `0x40` bedeutet also 40.
        case dezimal
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
    /// Im Fall `.siebenBit` wird **nicht** skaliert — der Wert ist bereits die
    /// Velocity. Quelle: OpenMPT `Load_med.cpp`, Befehl 0x0C, dritte
    /// Verzweigung (`(param & 0x7F + 1) / 2` rechnet dort auf die interne
    /// 0–64-Skala herunter).
    ///
    /// Werte ab `0x80` setzen laut Handbuch die Grundlautstärke des
    /// Instruments (`$80`–`$C0` für 0–64) statt die Notenlautstärke. In den
    /// sieben Testdateien kommt das in über 11 000 `0C`-Befehlen **kein
    /// einziges Mal** vor; die Diagnose meldet es, falls doch.
    public static func velocity(ausBefehlsdaten byte: UInt8,
                                lesart: Lautstärkelesart) -> UInt8 {
        if byte >= 0x80 { return 0 }   // setzt die Grundlautstärke, keine Note
        switch lesart {
        case .siebenBit:
            return byte & 0x7F
        case .hexadezimal:
            return UInt8(min(min(Int(byte), 64) * 127 / 64, 127))
        case .dezimal:
            let wert = Int(byte >> 4) * 10 + Int(byte & 0x0F)
            return UInt8(min(wert * 127 / 64, 127))
        }
    }

    /// Grundlautstärke, die ein `0C`-Wert ab `0x80` setzt (0–64), sonst `nil`.
    public static func grundlautstärke(ausBefehlsdaten byte: UInt8) -> UInt8? {
        byte >= 0x80 ? min(byte - 0x80, 64) : nil
    }

    /// Instrument-Grundlautstärke `svol` (0–64) in den MIDI-Bereich.
    ///
    /// Dies ist **belegt**, anders als die Velocity oben: Das undokumentierte
    /// Feld der 24-Byte-`InstrExt` enthält genau diesen Wert, und der Vergleich
    /// ergab `svol × 2`, gedeckelt bei 127 — 47→94, 49→98, 48→96, 64→127,
    /// 32→64, 50→100. Alle sechs Messwerte passen.
    public static func midiLautstärke(ausSvol svol: UInt8) -> UInt8 {
        UInt8(min(Int(svol) * 2, 127))
    }
}
