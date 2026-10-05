import Foundation
import CryptoKit

/// Schreibt die SysEx-Dumps eines Songs als `.syx`-Dateien.
///
/// Zweck: Die Klangeinstellungen zurück in den MU80 bringen, ohne den Umweg
/// über den Emulator. Erst damit lässt sich beurteilen, ob ein späterer
/// MIDI-Export richtig klingt — sonst hört man nur, dass etwas anders ist,
/// aber nicht, ob es an den Noten oder an der Instrumentierung liegt.
public enum SysExExport {

    /// Was über einen Dump bekannt ist.
    public struct DumpInfo: Sendable {
        public let index: Int
        public let name: String
        public let fileName: String
        public let byteCount: Int
        public let messageCount: Int
        /// SHA-256, gekürzt — erkennt gleiche Klangsätze über Songs hinweg.
        public let hash: String
        public let manufacturer: UInt8?
        /// Welche Model-IDs vorkommen. `0x4C` = XG, `0x49` = MU80-eigen.
        public let modelIDs: [UInt8]
        public let complete: Bool
        /// Ergebnis der Nachrichtenprüfung (Byteanzahl und Prüfsumme je Nachricht).
        public let check: SysExDump.Check
        /// Bytes, die beim Schreiben beweisbar repariert wurden.
        public let repairs: [SysExRepair.Change]
        /// Beanstandungen, die sich nicht beweisbar beheben ließen.
        public let unresolved: [String]
        /// Wird der Dump im Songverlauf per Befehl `10` ausgelöst?
        public let triggeredAt: SourceLocation?
    }

    public struct Result: Sendable {
        public let folder: URL
        public let dumps: [DumpInfo]
    }

    /// Schreibt alle Dumps nach `folder` und gibt das Verzeichnis zurück.
    ///
    /// Der Rohstrom wird unverändert geschrieben: Er ist bereits eine gültige
    /// Folge von `F0…F7`-Nachrichten (gemessen: 404 bis 408 Stück je Dump).
    @discardableResult
    public static func write(song: Song, to folder: URL) throws -> Result {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let triggers = triggerLocations(in: song)
        var infos: [DumpInfo] = []

        for dump in song.dumps {
            let base = fileNameBase(song: song, dump: dump)
            let url = folder.appendingPathComponent(base + ".syx")

            // Beweisbar beschädigte Bytes richtigstellen. Die Originaldatei
            // bleibt unberührt; die `.syx` ist zum Senden gedacht, und ein
            // Gerät lehnt eine kaputte Nachricht ab. Jede Änderung steht im
            // Manifest, geraten wird nichts.
            let repariert = SysExRepair.repair(dump)
            try Data(repariert.data).write(to: url)
            let geschrieben = SysExDump(index: dump.index, name: dump.name,
                                        rawData: repariert.data)

            infos.append(DumpInfo(
                index: dump.index,
                name: dump.name,
                fileName: url.lastPathComponent,
                byteCount: geschrieben.rawData.count,
                messageCount: geschrieben.messages.count,
                hash: shortHash(geschrieben.rawData),
                manufacturer: geschrieben.manufacturer,
                modelIDs: modelIDs(of: geschrieben),
                complete: geschrieben.isComplete,
                check: geschrieben.check(),
                repairs: repariert.changes,
                unresolved: repariert.unresolved,
                triggeredAt: triggers[dump.index]))
        }

        let result = Result(folder: folder, dumps: infos)
        try writeManifest(song: song, result: result)
        return result
    }

    // MARK: - Hilfen

    /// Model-IDs, die in den Nachrichten eines Dumps vorkommen.
    /// Yamaha legt sie auf Byte 3: `F0 43 0n <model> …`
    /// Was an einem Dump repariert wurde, für das Manifest.
    ///
    /// Steht ausführlich da, weil es eine Änderung an den Daten des Autors ist
    /// — wenn auch nur in der Ausgabedatei. Wer sie nachvollziehen will, soll
    /// jedes Byte wiederfinden.
    static func reparaturText(_ d: DumpInfo) -> String {
        guard !d.repairs.isEmpty || !d.unresolved.isEmpty else { return "" }
        var zeilen = [""]
        if !d.repairs.isEmpty {
            zeilen.append("     Repariert  : \(d.repairs.count) beschädigte Bytes. Die "
                        + "Originaldatei bleibt unberührt;")
            zeilen.append("                  diese .syx trägt die Korrektur, damit das Gerät "
                        + "sie annimmt.")
            for c in d.repairs {
                zeilen.append(String(format: "                  Offset %6d: %02X → %02X",
                                     c.offset, c.from, c.to))
                zeilen.append("                      \(c.reason)")
            }
        }
        if !d.unresolved.isEmpty {
            zeilen.append("     Offen      : \(d.unresolved.count) Beanstandungen ohne "
                        + "beweisbare Reparatur —")
            zeilen.append("                  unverändert gelassen.")
            for u in d.unresolved.prefix(10) { zeilen.append("                  \(u)") }
        }
        return zeilen.joined(separator: "\n")
    }

    static func modelIDs(of dump: SysExDump) -> [UInt8] {
        var seen: [UInt8] = []
        for message in dump.messages where message.count > 3 {
            let id = message[message.startIndex + 3]
            if !seen.contains(id) { seen.append(id) }
        }
        return seen
    }

    static func shortHash(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).compactMap { String(format: "%02x", $0) }
            .joined().prefix(12).description
    }

    /// Fundstellen des Befehls `10` (SysEx senden), nach Dumpnummer.
    /// Das Datenbyte benennt den Dump.
    static func triggerLocations(in song: Song) -> [Int: SourceLocation] {
        var found: [Int: SourceLocation] = [:]
        for block in song.blocks {
            for row in 0..<block.rows {
                for track in 0..<block.tracks {
                    for page in 0..<block.pageCount {
                        let c = block.command(row: row, track: track, page: page)
                        guard c.number == 0x10 else { continue }
                        let i = Int(c.data)
                        if found[i] == nil {
                            found[i] = SourceLocation(block: block.number, blockname: block.name,
                                                      row: row, track: track, page: page)
                        }
                    }
                }
            }
        }
        return found
    }

    static func fileNameBase(song: Song, dump: SysExDump) -> String {
        let songPart = sanitised(song.name.isEmpty
            ? (song.fileName as NSString).deletingPathExtension : song.name)
        let namePart = dump.name.isEmpty ? "" : "-" + sanitised(dump.name)
        return String(format: "%@-dump%02d%@", songPart, dump.index, namePart)
    }

    static func sanitised(_ s: String) -> String {
        let erlaubt = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let gefiltert = s.unicodeScalars.map { erlaubt.contains($0) ? Character($0) : "_" }
        return String(gefiltert).replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    // MARK: - Manifest

    static func writeManifest(song: Song, result: Result) throws {
        var text = """
        SysEx-Dumps aus \(song.fileName)
        \(String(repeating: "=", count: 40))

        Song     : \(song.name.isEmpty ? "—" : song.name)
        Format   : \(song.version.name)
        Dumps    : \(result.dumps.count)


        """
        for d in result.dumps {
            let model = d.modelIDs.map { id -> String in
                switch id {
                case 0x4C: return "4C (XG)"
                case 0x49: return "49 (MU80)"
                default:   return String(format: "%02X", id)
                }
            }.joined(separator: ", ")
            let status = d.triggeredAt.map { "im Songverlauf gesendet — \($0)" }
                ?? "nur gespeichert, nicht ausgelöst"
            text += """
            [\(d.index)] \(d.name.isEmpty ? "(ohne Namen)" : d.name)
                 Datei      : \(d.fileName)
                 Größe      : \(d.byteCount) Bytes, \(d.messageCount) Nachrichten
                 Prüfsumme  : \(d.hash)
                 Hersteller : \(d.manufacturer.map { String(format: "0x%02X", $0) } ?? "—")\
            \(d.manufacturer == 0x43 ? " (Yamaha)" : "")
                 Model-IDs  : \(model)
                 Form       : \(d.complete ? "F0 … F7 vollständig" : "UNVOLLSTÄNDIG")
                 Prüfung    : \(d.check.text)\(reparaturText(d))
                 Status     : \(status)


            """
        }
        text += """
        Hinweis zum Senden
        ------------------
        Die .syx-Dateien enthalten den Rohstrom, wie er in der Songdatei steht —
        eine Folge einzelner F0…F7-Nachrichten. Zum Übertragen eignet sich auf
        dem Mac etwa SysEx Librarian.

        Bei über 400 Nachrichten je Dump kann der Eingangspuffer des Geräts
        überlaufen. Wenn Klänge fehlen, hilft eine Pause zwischen den
        Nachrichten (SysEx Librarian: „Pause between messages", 20–50 ms).

        """
        try text.write(to: result.folder.appendingPathComponent("dumps.txt"),
                       atomically: true, encoding: .utf8)

        // Die Part-Belegung daneben legen. Sie steht in den Dumps, ist in
        // deren Rohbytes aber nicht lesbar — und beim Neuinstrumentieren ist
        // sie das Wichtigste, was die MED-Datei nicht hergibt: welcher Klang
        // auf welchem Kanal lag, und wo mehrere Parts übereinanderliegen.
        try PartListing.text(for: song)
            .write(to: result.folder.appendingPathComponent("parts.txt"),
                   atomically: true, encoding: .utf8)
    }
}
