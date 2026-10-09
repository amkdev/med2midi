import Foundation

/// Repariert einzelne gekippte Bits in einem SysEx-Dump.
///
/// **Nur beweisbare Fälle.** Jede Änderung muss sich aus der Nachricht selbst
/// oder aus ihren Geschwistern ergeben; geraten wird nichts. Was sich nicht
/// beweisen lässt, bleibt stehen und wird gemeldet.
///
/// Anlass war `2_ENDZEIT_NEW.OMP_WS+MU`: Der MU80 meldete beim Empfang
/// „Check Sum Error!". Fünf Bytes waren beschädigt, jedes auf Bitebene —
/// vermutlich ein defekter Sektor auf der Amiga-Diskette.
public enum SysExRepair {

    public struct Change: Sendable {
        public let offset: Int
        public let from: UInt8
        public let to: UInt8
        public let reason: String
    }

    public struct Result: Sendable {
        public let data: [UInt8]
        public let changes: [Change]
        /// Beanstandungen, die sich nicht beweisbar beheben ließen.
        public let unresolved: [String]

        public var isClean: Bool { changes.isEmpty && unresolved.isEmpty }
    }

    /// Yamaha-Prüfsumme über Byteanzahl, Adresse und Daten.
    static func checksum(_ m: ArraySlice<UInt8>) -> UInt8 {
        let sum = m[(m.startIndex + 4)..<(m.endIndex - 2)].reduce(0) { $0 + Int($1) }
        return UInt8((128 - (sum & 0x7F)) & 0x7F)
    }

    static func declaredCount(_ m: ArraySlice<UInt8>) -> Int {
        Int(m[m.startIndex + 4]) << 8 | Int(m[m.startIndex + 5])
    }

    static func isValid(_ m: ArraySlice<UInt8>) -> Bool {
        m.count >= 11 && m.first == 0xF0 && m.last == 0xF7
            && declaredCount(m) == m.count - 11
            && checksum(m) == m[m.endIndex - 2]
    }

    public static func repair(_ dump: SysExDump) -> Result {
        guard dump.manufacturer == 0x43 else {
            return Result(data: dump.rawData, changes: [], unresolved: [])
        }
        var bytes = dump.rawData
        var changes: [Change] = []

        changes += repairFraming(&bytes)
        let (dataChanges, unresolved) = repairDataBytes(&bytes)
        changes += dataChanges

        return Result(data: bytes, changes: changes.sorted { $0.offset < $1.offset },
                      unresolved: unresolved)
    }

    // MARK: - Rahmen

    /// Stellt `F0` und `F7` wieder her, wo die Nachricht danach aufgeht.
    ///
    /// Beweis: Eine SysEx-Nachricht kann nicht anders als mit `F0` beginnen
    /// und mit `F7` enden, und die reparierte Nachricht muss anschließend
    /// Byteanzahl **und** Prüfsumme erfüllen. Trifft das nicht zu, bleibt das
    /// Byte stehen.
    static func repairFraming(_ bytes: inout [UInt8]) -> [Change] {
        var changes: [Change] = []
        var i = 0
        while i < bytes.count {
            guard let end = bytes[i...].firstIndex(of: 0xF7) else { break }

            // Fall 1: Das Startbyte ist beschädigt.
            if bytes[i] != 0xF0 {
                let alt = bytes[i]
                bytes[i] = 0xF0
                if isValid(bytes[i...end]) {
                    changes.append(Change(offset: i, from: alt, to: 0xF0,
                                          reason: "Startbyte; Nachricht danach vollständig gültig"))
                } else {
                    bytes[i] = alt
                }
            }

            // Fall 2: Das Endbyte ist beschädigt, zwei Nachrichten hängen
            // zusammen. Die deklarierte Byteanzahl sagt, wo das `F7` gehört.
            if bytes[i] == 0xF0, i + 10 < bytes.count {
                let soll = i + declaredCount(bytes[i..<min(i + 11, bytes.count)]) + 10
                if soll < end, soll < bytes.count, bytes[soll] != 0xF7 {
                    let alt = bytes[soll]
                    bytes[soll] = 0xF7
                    if isValid(bytes[i...soll]) {
                        changes.append(Change(offset: soll, from: alt, to: 0xF7,
                            reason: "Endbyte; zwei Nachrichten hingen zusammen"))
                    } else {
                        bytes[soll] = alt
                    }
                }
            }

            guard let neuesEnde = bytes[i...].firstIndex(of: 0xF7) else { break }
            i = neuesEnde + 1
        }
        return changes
    }

    // MARK: - Datenbytes

    /// Ein beschädigtes Datenbyte über den Vergleich mit Geschwistern finden.
    ///
    /// Zwei Nachrichten sind **Geschwister**, wenn sie gleich lang sind und
    /// sich ihre Adresse in genau einem der drei Bytes unterscheidet. Beim
    /// MU80 trifft das auf die vier Drum-Setups (`30`–`33`) und auf dieselbe
    /// Parameterstelle verschiedener Parts (`08 nn xx`) zu.
    ///
    /// Repariert wird nur, wenn **alle** Geschwister an genau einer Stelle
    /// übereinstimmen, die beanstandete Nachricht dort abweicht, und die
    /// Abweichung die Prüfsummendifferenz **exakt** erklärt. Dann stimmt
    /// anschließend die gespeicherte Prüfsumme wieder — der Beweis liegt in
    /// der Nachricht selbst.
    static func repairDataBytes(_ bytes: inout [UInt8]) -> ([Change], [String]) {
        var spans: [(start: Int, end: Int)] = []
        var i = 0
        while i < bytes.count, bytes[i] == 0xF0 {
            guard let end = bytes[i...].firstIndex(of: 0xF7) else { break }
            spans.append((i, end))
            i = end + 1
        }

        func address(_ s: (start: Int, end: Int)) -> [UInt8] {
            Array(bytes[(s.start + 6)...(s.start + 8)])
        }

        var changes: [Change] = []
        var unresolved: [String] = []

        for span in spans where !isValid(bytes[span.start...span.end]) {
            let m = bytes[span.start...span.end]
            guard m.count >= 11, declaredCount(m) == m.count - 11 else {
                unresolved.append(describe(m, "Byteanzahl passt nicht zur Länge"))
                continue
            }
            // Um wie viel muss sich die Summe ändern, damit die gespeicherte
            // Prüfsumme wieder stimmt? Modulo 128 gerechnet, damit es in
            // beide Richtungen trägt: Ein Datenbyte kann zu niedrig **oder**
            // zu hoch sein, und beide Fälle kommen im Material vor.
            let fehlend = (Int(checksum(m)) - Int(m[m.endIndex - 2]) + 128) % 128
            guard fehlend != 0 else { continue }

            let adresse = address(span)
            let geschwister = spans.filter { other in
                other.start != span.start
                    && other.end - other.start == span.end - span.start
                    && zip(address(other), adresse).filter { $0 != $1 }.count == 1
            }
            guard geschwister.count >= 3 else {
                unresolved.append(describe(m, "Prüfsumme weicht ab, "
                                           + "zu wenige Geschwister zum Vergleich"))
                continue
            }

            // Stellen, an denen alle Geschwister einig sind und diese
            // Nachricht genau um `fehlend` darunter liegt.
            let datenAb = span.start + 9, datenBis = span.end - 2
            var kandidaten: [(offset: Int, soll: UInt8)] = []
            for o in datenAb..<datenBis {
                let versatz = o - span.start
                let werte = geschwister.map { bytes[$0.start + versatz] }
                guard let erster = werte.first, werte.allSatisfy({ $0 == erster }) else { continue }
                guard bytes[o] != erster,
                      (Int(erster) - Int(bytes[o]) + 128) % 128 == fehlend else { continue }
                kandidaten.append((o, erster))
            }

            guard kandidaten.count == 1 else {
                unresolved.append(describe(m, kandidaten.isEmpty
                    ? "Prüfsumme weicht um \(fehlend) ab, kein eindeutiges Byte gefunden"
                    : "Prüfsumme weicht um \(fehlend) ab, \(kandidaten.count) mögliche Bytes"))
                continue
            }

            let k = kandidaten[0]
            let alt = bytes[k.offset]
            bytes[k.offset] = k.soll
            guard isValid(bytes[span.start...span.end]) else {
                bytes[k.offset] = alt
                unresolved.append(describe(m, "Reparatur hätte die Prüfsumme nicht erfüllt"))
                continue
            }
            let adrText = adresse.map { String(format: "%02X", $0) }.joined(separator: " ")
            changes.append(Change(offset: k.offset, from: alt, to: k.soll,
                reason: "Datenbyte in Adresse \(adrText); alle "
                      + "\(geschwister.count) vergleichbaren Nachrichten haben dort "
                      + String(format: "%02X", k.soll)
                      + ", und damit stimmt die gespeicherte Prüfsumme wieder"))
        }
        return (changes, unresolved)
    }

    static func describe(_ m: ArraySlice<UInt8>, _ grund: String) -> String {
        guard m.count >= 9 else { return grund }
        let adresse = m[(m.startIndex + 6)...(m.startIndex + 8)]
            .map { String(format: "%02X", $0) }.joined(separator: " ")
        return "Adresse \(adresse): \(grund)"
    }
}
