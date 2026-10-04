import Foundation

/// Eine Zelle: Note, Instrument und der Befehl der ersten Befehlsseite.
/// Weitere Seiten stehen in `Block.extraPages`.
public struct Cell: Equatable, Sendable {
    public let note: UInt8          // 0 = ---, 1 = C-1
    public let instrument: UInt8    // 0 = keines
    public let command: Command

    public init(note: UInt8, instrument: UInt8, command: Command) {
        self.note = note
        self.instrument = instrument
        self.command = command
    }

    public static let empty = Cell(note: 0, instrument: 0,
                                   command: Command(number: 0, data: 0))

    /// Notenname wie in OctaMED: 1 = C-1, 2 = C#1 …
    public var noteName: String {
        guard note > 0 else { return "---" }
        let names = ["C-", "C#", "D-", "D#", "E-", "F-",
                     "F#", "G-", "G#", "A-", "A#", "B-"]
        let n = Int(note) - 1
        return "\(names[n % 12])\(n / 12 + 1)"
    }
}

public struct Block: Sendable {
    public let number: Int
    public let name: String
    public let tracks: Int
    public let rows: Int
    /// Zeile-vor-Spur, wie in der Datei: `cells[row * tracks + track]`.
    public let cells: [Cell]
    /// Zusätzliche Befehlsseiten (`BlockCmdPageTable`), je 2 Bytes pro Zelle,
    /// gleiche Anordnung. Leer, wenn der Block nur eine Seite hat.
    public let extraPages: [[Command]]
    /// Zweites Parameterbyte je Zelle aus der **Befehlserweiterung**.
    ///
    /// Der Zeiger darauf steht in `BlockInfo` auf dem ersten der fünf Felder,
    /// die Kinnunens Spezifikation als `reserved[5]` führt — undokumentiert.
    /// Gefunden über OpenMPT `Load_med.cpp` (`MMDBlockInfo.cmdExtTableOffset`).
    /// Die Tabelle enthält ein Byte je Zelle und Befehlsseite.
    /// Leer, wenn der Block keine Erweiterung hat.
    public let extraParameters: [[UInt8]]

    /// Trägt der Block eine Befehlserweiterung, sind Lautstärkewerte 7-bittig
    /// (0–127) statt 0–64. Quelle: OpenMPT setzt dort `vol7bit`.
    public var sevenBitVolume: Bool { !extraParameters.isEmpty }

    public init(number: Int, name: String, tracks: Int, rows: Int,
                cells: [Cell], extraPages: [[Command]],
                extraParameters: [[UInt8]] = []) {
        self.number = number; self.name = name
        self.tracks = tracks; self.rows = rows
        self.cells = cells; self.extraPages = extraPages
        self.extraParameters = extraParameters
    }

    /// Zweites Parameterbyte einer Zelle, falls vorhanden.
    public func extraParameters(row: Int, track: Int, page: Int = 0) -> UInt8? {
        guard page < extraParameters.count else { return nil }
        let i = row * tracks + track
        return i < extraParameters[page].count ? extraParameters[page][i] : nil
    }

    public func cell(row: Int, track: Int) -> Cell {
        guard row >= 0, row < rows, track >= 0, track < tracks else { return .empty }
        return cells[row * tracks + track]
    }

    /// Befehl einer bestimmten Seite. Seite 0 ist die Hauptseite.
    public func command(row: Int, track: Int, page: Int) -> Command {
        if page == 0 { return cell(row: row, track: track).command }
        let i = page - 1
        guard i < extraPages.count else { return Command(number: 0, data: 0) }
        let index = row * tracks + track
        guard index < extraPages[i].count else { return Command(number: 0, data: 0) }
        return extraPages[i][index]
    }

    public var pageCount: Int { 1 + extraPages.count }

    /// Zahl der Haltezeilen hinter einer Note: Zellen, die **nur** die
    /// Instrumentnummer tragen, ohne Note und ohne Befehl.
    ///
    /// OctaMED zeichnet sie als senkrechten Strich in der Notenspalte. Am
    /// Original gemessen bestimmen sie die Grundlänge der Note; der Hold-Wert
    /// des Instruments kommt in Ticks obendrauf. Siehe `Timing.noteDuration`.
    public func holdRows(afterRow row: Int, track: Int) -> Int {
        guard row >= 0, row < rows, track >= 0, track < tracks else { return 0 }
        let instrument = cell(row: row, track: track).instrument
        guard instrument != 0 else { return 0 }
        var n = 0
        var r = row + 1
        while r < rows {
            let z = cell(row: r, track: track)
            guard z.note == 0, z.instrument == instrument, z.command.isEmpty else { break }
            // Auch die Zusatzseiten müssen leer sein.
            var leer = true
            for page in 1..<pageCount where !command(row: r, track: track, page: page).isEmpty {
                leer = false
            }
            guard leer else { break }
            n += 1
            r += 1
        }
        return n
    }
}

public struct Instrument: Sendable {
    public let number: Int          // 1-basiert wie in der Anzeige
    public let name: String
    public let midiChannel: UInt8     // 0 = kein MIDI
    public let midiPreset: UInt8
    public let longPreset: UInt16?
    public let defaultVolume: UInt8   // svol, 0–64
    public let transpose: Int8
    public let hold: UInt8?
    public let decay: UInt8?
    public let suppressNoteOff: Bool?
    /// Undokumentiertes Feld der 24-Byte-InstrExt: Lautstärke im MIDI-Bereich.
    public let midiVolume: UInt8?
    /// Ob die Datei Sampledaten für dieses Instrument enthält.
    /// Spezifikation zu `smplarr`: "This pointer is zero in OctaMED Pro MMD1
    /// songs. In this case, OctaMED Pro loads the instruments from disk(s)."
    /// Ein Nicht-MIDI-Instrument ohne Sampledaten kann nichts erzeugen.
    public let hasSampleData: Bool

    public var isMIDI: Bool { midiChannel > 0 }
    public var sounds: Bool { isMIDI && defaultVolume > 0 }

    /// Anfangslautstärke als MIDI-Velocity.
    ///
    /// Immer aus `svol` gerechnet, auch wenn das undokumentierte Feld
    /// vorliegt. Die Abspielroutine kennt nur **eine** Lautstärke je Spur:
    /// Jede Zelle mit Instrumentnummer setzt sie auf `inst_svol`, Befehl `0C`
    /// überschreibt dasselbe Feld, und was danach hinausgeht, nimmt denselben
    /// Weg. Zwei Umrechnungen kann es nicht geben.
    ///
    /// Das Feld `midiVolume` enthält `svol × 2` (gemessen: 47→94, 50→100),
    /// die Messung am MIDI-Ausgang ergibt dagegen `⌊svol × 127/64⌋` —
    /// `C40` in Dezimalanzeige wurde als Velocity 79 empfangen, nicht 80.
    /// Beides unterscheidet sich um genau eins. Das Dateifeld bleibt
    /// zugänglich, aber es ist nicht die gesendete Velocity.
    public var initialMIDIVolume: UInt8 {
        CommandCatalog.midiVolume(ausSvol: defaultVolume)
    }
}

public struct SysExDump: Sendable {
    public let index: Int
    public let name: String
    public let rawData: [UInt8]

    /// Ein "Dump" ist in der Praxis eine Folge einzelner SysEx-Nachrichten.
    /// Gemessen: 408 Nachrichten in 13 154 Bytes.
    public var messages: [ArraySlice<UInt8>] {
        var result: [ArraySlice<UInt8>] = []
        var i = rawData.startIndex
        while i < rawData.endIndex, rawData[i] == 0xF0 {
            guard let end = rawData[i...].firstIndex(of: 0xF7) else { break }
            result.append(rawData[i...end])
            i = rawData.index(after: end)
        }
        return result
    }

    public var isComplete: Bool {
        rawData.first == 0xF0 && rawData.last == 0xF7
    }

    /// Herstellerkennung der ersten Nachricht. 0x43 = Yamaha.
    public var manufacturer: UInt8? {
        rawData.count > 1 ? rawData[1] : nil
    }

    /// Befund der Nachrichtenprüfung.
    public struct Check: Sendable {
        public let messages: Int
        /// Nachrichten, deren deklarierte Byteanzahl zur Datenlänge passt.
        public let countsValid: Int
        /// Nachrichten mit gültiger Yamaha-Prüfsumme.
        public let checksumsValid: Int
        /// Bytes, die nach der letzten vollständigen Nachricht übrig bleiben.
        public let trailingBytes: Int

        public var isIntact: Bool {
            messages > 0 && countsValid == messages
                && checksumsValid == messages && trailingBytes == 0
        }
    }

    /// Prüft jede Nachricht einzeln.
    ///
    /// Eine Sollgröße für den ganzen Dump gibt es nicht — jede Nachricht trägt
    /// ihre Byteanzahl selbst, die Gesamtlänge folgt aus dem Inhalt. Prüfbar
    /// ist stattdessen jede Nachricht für sich, und das ist stärker.
    ///
    /// Aufbau: `F0 43 0n mm bh bl <Adresse+Daten> cs F7`. Die Prüfsumme ist
    /// Yamahas Zweierkomplement über Byteanzahl, Adresse und Daten:
    /// `cs = (128 − (Summe & 0x7F)) & 0x7F`.
    ///
    /// **Am Material belegt:** Alle 4480 Nachrichten der 11 Dumps bestehen
    /// beide Prüfungen, ohne Restbyte.
    public func check() -> Check {
        var counts = 0, sums = 0
        let list = messages
        for m in list {
            guard m.count >= 11 else { continue }
            let base = m.startIndex
            let declared = Int(m[base + 4]) << 8 | Int(m[base + 5])
            // Byteanzahl zählt die Daten ohne die drei Adressbytes.
            if m.count - 11 == declared { counts += 1 }
            var sum = 0
            for b in m[(base + 4)..<(m.endIndex - 2)] { sum += Int(b) }
            if (128 - (sum & 0x7F)) & 0x7F == Int(m[m.endIndex - 2]) { sums += 1 }
        }
        let consumed = list.reduce(0) { $0 + $1.count }
        return Check(messages: list.count, countsValid: counts,
                     checksumsValid: sums, trailingBytes: rawData.count - consumed)
    }
}

public struct PlaySequence: Sendable {
    public let name: String
    public let blocks: [Int]
}

public struct Song: Sendable {
    public let version: MMDVersion
    public let name: String
    public let fileName: String
    public let modlen: UInt32
    public let fileSize: Int
    public let extraSongs: Int

    public let defaultTempo: UInt16
    public let ticksPerRow: UInt8
    public let bpmMode: Bool
    public let rowsPerBeat: Int
    public let songTranspose: Int8
    public let mixingMode: Bool
    /// Lesart der `0C`-Werte für einen Block.
    public func volumeEncoding(block: Block) -> CommandCatalog.VolumeEncoding {
        if block.sevenBitVolume { return .sevenBit }
        return volumeIsHex ? .hexadecimal : .decimal
    }

    /// `FLAG_VOLHEX` — ob Lautstärkewerte hexadezimal zu lesen sind.
    /// Wird beim Abspielen ausgewertet, nicht nur bei der Anzeige: dieselben
    /// Patterndaten ergeben je nach Modus verschiedene MIDI-Velocities.
    public let volumeIsHex: Bool

    public let instruments: [Instrument]
    public let blocks: [Block]
    public let playSequences: [PlaySequence]
    public let sections: [Int]
    public let dumps: [SysExDump]
    /// Controller-Nummern für die Befehle 31–3F, aus `MMDMIDICmd3x`.
    public let cmd3xControllers: [(typ: UInt8, number: UInt16)]

    public let diagnostics: Diagnostics
}
