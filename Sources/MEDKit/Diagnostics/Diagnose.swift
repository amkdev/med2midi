import Foundation

/// Fundstelle einer Auffälligkeit — so genau, dass man sie im Emulator
/// anfahren kann.
public struct Fundstelle: Equatable, Sendable, CustomStringConvertible {
    public let block: Int
    public let blockname: String
    public let zeile: Int
    public let spur: Int
    public let seite: Int

    public var description: String {
        let bn = blockname.isEmpty ? "" : " [\(blockname)]"
        let s = seite == 0 ? "" : " Seite \(seite + 1)"
        return "Block \(block)\(bn) Zeile \(zeile) Spur \(spur)\(s)"
    }
}

public struct Warnung: Sendable, CustomStringConvertible {
    public enum Art: Sendable {
        case unbekannterBefehl(nummer: UInt8, daten: UInt8)
        case befehlOhneWirkungBeiMIDI(nummer: UInt8)
        case kanalKollision(kanal: UInt8, instrumente: [Int])
        case velocityÜberBereich(wert: UInt8)
        case modlenStimmtNicht(modlen: UInt32, dateigröße: Int)
        case instrExtUngewöhnlich(größe: UInt16)
        case dumpUnvollständig(index: Int)
        case cmd3xFehlt(befehl: UInt8)
        case notenOhneMIDIKanal(instrument: Int, name: String, noten: Int)
        case befehlMitAuffälligemWertebereich(nummer: UInt8, werte: [UInt8])
        case volhexUnplausibel(laut: String, sättigungLaut: Int, sättigungAndere: Int)
        case sonstiges(String)
    }

    public let art: Art
    public let fundstellen: [Fundstelle]
    public let anzahl: Int

    public var description: String {
        let text: String
        switch art {
        case .unbekannterBefehl(let n, let d):
            text = "Unbekannter Befehl \(String(format: "%02X%02X", n, d))"
        case .befehlOhneWirkungBeiMIDI(let n):
            text = "Befehl \(String(format: "%02X", n)) hat bei MIDI-Instrumenten keine Wirkung"
        case .kanalKollision(let k, let i):
            text = "MIDI-Kanal \(k): mehrere klingende Instrumente \(i)"
        case .velocityÜberBereich(let w):
            text = "Velocity-Werte über \(w): werden beim Skalieren alle zu 127 (Dynamik geht verloren)"
        case .modlenStimmtNicht(let m, let d):
            text = "modlen \(m) weicht von der Dateigröße \(d) ab"
        case .instrExtUngewöhnlich(let g):
            text = "InstrExt-Eintragsgröße \(g) Bytes (dokumentiert sind 18)"
        case .dumpUnvollständig(let i):
            text = "Dump \(i) beginnt nicht mit F0 oder endet nicht mit F7"
        case .cmd3xFehlt(let b):
            text = "Befehl \(String(format: "%02X", b)) benutzt, aber keine Cmd3x-Tabelle vorhanden"
        case .notenOhneMIDIKanal(let i, let n, let noten):
            text = "Instrument \(i)\(n.isEmpty ? "" : " „\(n)“") hat keinen MIDI-Kanal, "
                 + "wird aber mit \(noten) Noten gespielt — diese Noten erscheinen nicht im Export"
        case .befehlMitAuffälligemWertebereich(let nummer, let werte):
            text = "Befehl \(String(format: "%02X", nummer)) benutzt nur die Werte "
                 + werte.map(String.init).joined(separator: ", ")
                 + " — das passt nicht zu seiner MIDI-Bedeutung"
        case .volhexUnplausibel(let laut, let a, let b):
            text = "Lautstärke-Flag sagt „\(laut)“, aber dann sättigen \(a) % aller "
                 + "Velocities bei 127 (in der anderen Lesart nur \(b) %). "
                 + "Vermutlich wurde der Anzeigemodus umgeschaltet, ohne die Werte zu konvertieren."
        case .sonstiges(let s):
            text = s
        }
        let wo = fundstellen.isEmpty ? ""
            : "  —  \(fundstellen.prefix(3).map(\.description).joined(separator: "; "))"
            + (fundstellen.count > 3 ? " …" : "")
        return "\(text)  (\(anzahl)×)\(wo)"
    }
}

/// Hinweise sind keine Probleme, sondern erklären Auffälligkeiten, die Absicht
/// sind — etwa Controller-Spuren auf demselben Kanal.
public struct Hinweis: Sendable, CustomStringConvertible {
    public let text: String
    public var description: String { text }
}

public struct Diagnose: Sendable {
    public var warnungen: [Warnung]
    public var hinweise: [Hinweis]
    /// Befehlsnummer → Häufigkeit.
    public var befehlsStatistik: [UInt8: Int]
    /// Befehlsnummer → erste Fundstellen.
    public var befehlsFundstellen: [UInt8: [Fundstelle]]

    public var istSauber: Bool { warnungen.isEmpty }
}
