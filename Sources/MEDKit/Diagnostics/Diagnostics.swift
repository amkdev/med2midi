import Foundation

/// Fundstelle einer Auffälligkeit — so genau, dass man sie im Emulator
/// anfahren kann.
public struct SourceLocation: Equatable, Sendable, CustomStringConvertible {
    public let block: Int
    public let blockname: String
    public let row: Int
    public let track: Int
    public let page: Int

    public var description: String {
        let bn = blockname.isEmpty ? "" : " [\(blockname)]"
        let s = page == 0 ? "" : " Seite \(page + 1)"
        return "Block \(block)\(bn) Zeile \(row) Spur \(track)\(s)"
    }
}

public struct Warning: Sendable, CustomStringConvertible {
    public enum Kind: Sendable {
        case unknownCommand(number: UInt8, data: UInt8)
        case commandWithoutMIDIEffect(number: UInt8)
        case channelCollision(channel: UInt8, instruments: [Int])
        case modlenMismatch(modlen: UInt32, fileSize: Int)
        case unusualInstrExtSize(size: UInt16)
        case incompleteDump(index: Int, reason: String)
        case cmd3xMissing(command: UInt8)
        case notesWithoutMIDIChannel(instrument: Int, name: String, notes: Int)
        case commandWithOddValueRange(number: UInt8, values: [UInt8])
        case other(String)
    }

    public let art: Kind
    public let locations: [SourceLocation]
    public let count: Int

    public var description: String {
        let message: String
        switch art {
        case .unknownCommand(let n, let d):
            message = "Unbekannter Befehl \(String(format: "%02X%02X", n, d))"
        case .commandWithoutMIDIEffect(let n):
            message = "Befehl \(String(format: "%02X", n)) hat bei MIDI-Instrumenten keine Wirkung"
        case .channelCollision(let k, let i):
            message = "MIDI-Kanal \(k): mehrere klingende Instrumente \(i)"
        case .modlenMismatch(let m, let d):
            message = "modlen \(m) weicht von der Dateigröße \(d) ab"
        case .unusualInstrExtSize(let g):
            message = "InstrExt-Eintragsgröße \(g) Bytes (dokumentiert sind 18)"
        case .incompleteDump(let i, let grund):
            message = "Dump \(i): \(grund)"
        case .cmd3xMissing(let b):
            message = "Befehl \(String(format: "%02X", b)) benutzt, aber keine Cmd3x-Tabelle vorhanden"
        case .notesWithoutMIDIChannel(let i, let n, let notes):
            message = "Instrument \(i)\(n.isEmpty ? "" : " „\(n)“") hat keinen MIDI-Kanal, "
                 + "wird aber mit \(notes) Noten gespielt — diese Noten erscheinen nicht im Export"
        case .commandWithOddValueRange(let number, let values):
            message = "Befehl \(String(format: "%02X", number)) benutzt nur die Werte "
                 + values.map(String.init).joined(separator: ", ")
                 + " — das passt nicht zu seiner MIDI-Bedeutung"
        case .other(let s):
            message = s
        }
        let wo = locations.isEmpty ? ""
            : "  —  \(locations.prefix(3).map(\.description).joined(separator: "; "))"
            + (locations.count > 3 ? " …" : "")
        return "\(message)  (\(count)×)\(wo)"
    }
}

/// Hinweise sind keine Probleme, sondern erklären Auffälligkeiten, die Absicht
/// sind — etwa Controller-Spuren auf demselben Kanal.
public struct Notice: Sendable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public struct Diagnostics: Sendable {
    public var warnings: [Warning]
    public var notices: [Notice]
    /// Befehlsnummer → Häufigkeit.
    public var commandCounts: [UInt8: Int]
    /// Befehlsnummer → erste Fundstellen.
    public var commandLocations: [UInt8: [SourceLocation]]

    public var isClean: Bool { warnings.isEmpty }
}
