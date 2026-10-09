import Foundation

/// Liest aus einem Korg-Wavestation-Dump die Namen der gespeicherten Klänge.
///
/// **Warum das geht, obwohl der Dump undokumentiert ist:** Namen sind Text,
/// und Text fällt in Binärdaten auf. Entschlüsselt werden musste nur die
/// Verpackung; die Struktur ergibt sich danach aus den regelmäßigen Abständen.
///
/// Am Dump in `2_ENDZEIT_NEW.OMP_WS+MU` entwickelt und geprüft.
public enum Wavestation {

    public struct Entry: Sendable {
        public let index: Int
        public let name: String
        /// Ein Speicherplatz ohne Namen — am Gerät leer oder nie benannt.
        public var isEmpty: Bool { name.isEmpty }
    }

    public struct Contents: Sendable {
        /// Performances — was man am Gerät anwählt.
        public let performances: [Entry]
        /// Patches — die Bausteine, aus denen Performances bestehen.
        public let patches: [Entry]
        public var isEmpty: Bool { performances.isEmpty && patches.isEmpty }
    }

    /// Ob dieser Dump von einer Wavestation stammt.
    ///
    /// `F0 42 3n 28 …` — Korg, Format 3 mit Kanal `n`, Modell `28`.
    public static func isWavestation(_ dump: SysExDump) -> Bool {
        let b = dump.rawData
        return b.count > 5 && b[0] == 0xF0 && b[1] == 0x42
            && (b[2] & 0xF0) == 0x30 && b[3] == 0x28
    }

    /// Entpackt die Nutzlast.
    ///
    /// **Gemessen, nicht angenommen.** Korg verwendet in vielen Geräten eine
    /// 7-Bit-Packung, bei der acht MIDI-Bytes sieben Datenbytes tragen. Hier
    /// nicht: Von 134 602 Nutzbytes liegt genau eines über 15, und das ist das
    /// Prüfbyte am Ende. Es sind also **Nibbles**, und zwar das
    /// niederwertige zuerst — in der anderen Reihenfolge kommt kein Text
    /// heraus, in dieser 233 Fundstellen.
    ///
    /// Der Kopf ist fünf Bytes lang (`F0 42 3n 28 50`); mit sechs oder sieben
    /// verschiebt sich jedes Zeichen um ein halbes Byte, und die Namen werden
    /// unlesbar (`Ab{ovYllageo` statt `Dark Village`).
    public static func unpack(_ dump: SysExDump) -> [UInt8] {
        let b = dump.rawData
        guard isWavestation(dump), b.count > 7 else { return [] }
        var nibbles = Array(b[5..<(b.count - 1)])
        if nibbles.count % 2 == 1 { nibbles.removeLast() }

        var out: [UInt8] = []
        out.reserveCapacity(nibbles.count / 2)
        for i in stride(from: 0, to: nibbles.count, by: 2) {
            out.append((nibbles[i + 1] & 0x0F) << 4 | (nibbles[i] & 0x0F))
        }
        return out
    }

    /// Ein Namensfeld: 16 Bytes, druckbar oder `0x7F`, mit `0x00` am Ende.
    ///
    /// `0x7F` ist auf der Wavestation das Leerzeichen — `Dark\u{7F}Village`
    /// steht am Gerät als „Dark Village".
    /// Der Text eines Namensfelds, oder `nil`, wenn dort keines liegt.
    ///
    /// Ein **leeres** Feld (nur Leerzeichen) ist ein gültiges Feld und ergibt
    /// den leeren Text — das ist ein nie benannter Speicherplatz, und er muss
    /// mitgezählt werden, sonst verschiebt sich die Nummerierung aller
    /// folgenden Klänge.
    static func field(in bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 16 <= bytes.count, bytes[offset + 15] == 0 else { return nil }
        let core = bytes[offset..<(offset + 15)]
        guard core.allSatisfy({ (0x20...0x7E).contains($0) || $0 == 0x7F }) else { return nil }
        return String(core.map { $0 == 0x7F ? " " : Character(UnicodeScalar($0)) })
            .trimmingCharacters(in: .whitespaces)
    }

    /// Nur Felder mit erkennbarem Namen — für die Blocksuche.
    static func name(in bytes: [UInt8], at offset: Int) -> String? {
        guard let text = field(in: bytes, at: offset), text.count >= 3,
              text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return text
    }

    /// Sucht die Namensblöcke, statt Offsets festzunageln.
    ///
    /// Jeder Block ist eine Reihe von Namensfeldern in gleichem Abstand. Im
    /// Dump des Autors ergibt das zwei: Performances ab Offset 1813 im Abstand
    /// 181, Patches ab 20339 im Abstand 426. Gesucht wird trotzdem, weil die
    /// Zahlen aus **einem** Dump stammen und ein anderes Gerät oder eine
    /// andere Funktion sie verschieben kann.
    public static func read(_ dump: SysExDump) -> Contents {
        let bytes = unpack(dump)
        guard !bytes.isEmpty else { return Contents(performances: [], patches: []) }

        var found: [(offset: Int, name: String)] = []
        var i = 0
        while i < bytes.count - 16 {
            if let n = name(in: bytes, at: i) {
                found.append((i, n))
                i += 16
            } else {
                i += 1
            }
        }

        // Nach gleichem Abstand gruppieren.
        var groups: [[(offset: Int, name: String)]] = []
        var run: [(offset: Int, name: String)] = []
        var stride = 0
        for entry in found {
            if run.isEmpty { run = [entry]; stride = 0; continue }
            let d = entry.offset - run[run.count - 1].offset
            if run.count == 1 { stride = d; run.append(entry); continue }
            if d == stride { run.append(entry) }
            else {
                if run.count >= 8 { groups.append(run) }
                run = [entry]; stride = 0
            }
        }
        if run.count >= 8 { groups.append(run) }

        // Die beiden größten Blöcke: Performances zuerst, sie sind zahlreicher
        // und stehen vorn.
        let sorted = groups.sorted { $0.count > $1.count }
        let byPosition = sorted.prefix(2)
            .sorted { ($0.first?.offset ?? 0) < ($1.first?.offset ?? 0) }

        func complete(_ g: [(offset: Int, name: String)]?) -> (start: Int, stride: Int, entries: [Entry]) {
            guard let g, g.count > 1 else { return (0, 0, []) }
            let stride = g[1].offset - g[0].offset
            // Rückwärts bis zum ersten Platz, dann vorwärts bis zum letzten.
            var start = g[0].offset
            while field(in: bytes, at: start - stride) != nil { start -= stride }

            var entries: [Entry] = []
            var offset = start
            var lücken = 0
            while let text = field(in: bytes, at: offset) {
                entries.append(Entry(index: entries.count, name: text))
                if text.isEmpty { lücken += 1 } else { lücken = 0 }
                // Nach dem letzten Platz folgt irgendwann nur noch Füllung.
                if lücken > 4 {
                    entries.removeLast(lücken)
                    break
                }
                offset += stride
            }
            return (start, stride, entries)
        }

        var erster = complete(byPosition.first)
        let zweiter = complete(byPosition.count > 1 ? byPosition[1] : nil)

        // Die Blöcke dürfen sich nicht überlappen. Beim Dump des Autors reicht
        // die Rückwärtssuche des Patch-Blocks genau einen Platz in den
        // Performance-Block hinein — derselbe Speicherplatz zählte zweimal.
        // Abgeschnitten ergeben sich 100 Performances und 70 Patches, also
        // je zwei volle Bänke. Das ist die Gegenprobe, dass die Grenze stimmt.
        if zweiter.stride > 0, erster.stride > 0 {
            let überhang = erster.entries.indices.filter {
                erster.start + $0 * erster.stride >= zweiter.start
            }
            if let ab = überhang.first {
                erster = (erster.start, erster.stride, Array(erster.entries.prefix(ab)))
            }
        }
        return Contents(performances: erster.entries, patches: zweiter.entries)
    }
}
