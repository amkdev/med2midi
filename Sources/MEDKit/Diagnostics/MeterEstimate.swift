import Foundation

/// Grobe Schätzung der Taktart aus den Blocklängen.
///
/// **Ein Tracker speichert keine Taktart.** OctaMED kennt nur Zeilen je Beat
/// (LPB) und die Länge eines Blocks; den Takt hat der Autor über diese beiden
/// Größen und den Notenversatz ausgedrückt. Die Information steht also nicht
/// in der Datei und lässt sich nur eingrenzen.
///
/// Das Verfahren: Eine Taktlänge von `n` Vierteln kommt in Frage, wenn **jede**
/// vorkommende Blocklänge ein ganzes Vielfaches von `n × LPB` Zeilen ist. Das
/// grenzt ein, entscheidet aber nicht — bei 48, 96 und 192 Zeilen mit LPB 8
/// passen 2/4, 3/4 und 6/4 gleichermaßen.
///
/// Sendeblöcke bleiben außen vor: Ihre Länge ist die Ladezeit des MU80, nicht
/// Musik. Siehe `Block.isSysExSendBlock`.
public enum MeterEstimate {

    public struct Result: Sendable {
        /// Zeilen je Beat, aus der Songdatei.
        public let rowsPerBeat: Int
        /// Die vorkommenden Blocklängen in Zeilen, aufsteigend.
        public let blockRows: [Int]
        /// Ob jede Blocklänge überhaupt ganze Viertel ergibt.
        public let wholeBeats: Bool
        /// Taktlängen in Vierteln, die zu allen Blöcken passen.
        public let candidates: [Int]

        /// Einzeiler für die Anzeige.
        public var text: String {
            guard !blockRows.isEmpty else { return "keine Blöcke in der Reihenfolge" }
            guard wholeBeats else {
                return "Blocklängen ergeben keine ganzen Viertel — nicht eingrenzbar"
            }
            guard !candidates.isEmpty else {
                return "keine der üblichen Taktlängen passt zu allen Blöcken"
            }
            return "passt zu " + candidates.map { "\($0)/4" }.joined(separator: ", ")
        }

        /// Die Blocklängen in Vierteln, für die Anzeige.
        public var quarters: [String] {
            blockRows.map { rows in
                rows % rowsPerBeat == 0
                    ? "\(rows / rowsPerBeat)"
                    : String(format: "%.2f", Double(rows) / Double(rowsPerBeat))
            }
        }
    }

    /// Übliche Taktlängen in Vierteln. Mehr zu prüfen hilft nicht — je länger
    /// der Takt, desto eher passt er zufällig.
    static let usual = [2, 3, 4, 6]

    public static func estimate(song: Song) -> Result {
        let lpb = max(song.rowsPerBeat, 1)
        var rows = Set<Int>()
        for number in NoteAnalysis.songOrder(song) where number < song.blocks.count {
            let block = song.blocks[number]
            guard block.rows > 0, !block.isSysExSendBlock else { continue }
            rows.insert(block.rows)
        }
        let lengths = rows.sorted()
        let whole = !lengths.isEmpty && lengths.allSatisfy { $0 % lpb == 0 }
        let candidates = whole
            ? usual.filter { takt in lengths.allSatisfy { $0 % (takt * lpb) == 0 } }
            : []
        return Result(rowsPerBeat: lpb, blockRows: lengths,
                      wholeBeats: whole, candidates: candidates)
    }
}
