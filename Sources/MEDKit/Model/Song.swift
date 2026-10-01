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

    /// Anfangslautstärke für den Export. Wo das undokumentierte Feld vorliegt,
    /// ist es der genauere Wert — es ist bereits die Zahl, die das schreibende
    /// Programm gesendet hätte.
    public var initialMIDIVolume: UInt8 {
        midiVolume ?? CommandCatalog.midiVolume(ausSvol: defaultVolume)
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
