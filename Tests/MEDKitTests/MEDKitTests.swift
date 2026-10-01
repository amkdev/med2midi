import Testing
import Foundation
@testable import MEDKit

/// Die Songdateien sind privat und nicht versioniert. Tests, die sie brauchen,
/// überspringen sich sauber, wenn `songs/` fehlt.
enum TestFiles {
    static var folder: URL? {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { u.deleteLastPathComponent() }
        let songs = u.appendingPathComponent("songs")
        return FileManager.default.fileExists(atPath: songs.path) ? songs : nil
    }

    static func file(_ name: String) -> URL? {
        guard let o = folder else { return nil }
        let u = o.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static var all: [URL] {
        guard let o = folder else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: o,
            includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

// MARK: - Grundlagen ohne Testmaterial

@Test func versionFromSignature() {
    #expect(MMDVersion(signature: 0x4D4D4430) == .mmd0)
    #expect(MMDVersion(signature: 0x4D4D4433) == .mmd3)
    #expect(MMDVersion(signature: 0x4D4D4434) == nil)   // MMD4 ist reserviert
    #expect(MMDVersion(signature: 0x4D4F4430) == nil)   // "MOD0"
}

@Test func blockLayoutPerVersion() {
    #expect(MMDVersion.mmd0.noteBytes == 3)
    #expect(MMDVersion.mmd0.blockHeaderBytes == 2)
    #expect(MMDVersion.mmd1.noteBytes == 4)
    #expect(MMDVersion.mmd1.blockHeaderBytes == 8)
    #expect(MMDVersion.mmd3.hasSections)
    #expect(!MMDVersion.mmd1.hasSections)
}

@Test func noteNamesAsInOctaMED() {
    // Spezifikation: "0 = ---, 1 = C-1, 2 = C#1..."
    #expect(Cell(note: 0, instrument: 0, command: .init(number: 0, data: 0)).noteName == "---")
    #expect(Cell(note: 1, instrument: 0, command: .init(number: 0, data: 0)).noteName == "C-1")
    #expect(Cell(note: 2, instrument: 0, command: .init(number: 0, data: 0)).noteName == "C#1")
    #expect(Cell(note: 13, instrument: 0, command: .init(number: 0, data: 0)).noteName == "C-2")
}

@Test func commandZeroWithDataIsNotEmpty() {
    // Befehl 00 mit Datenbyte != 0 ist der MIDI-Controller-Wert.
    #expect(Command(number: 0, data: 0).isEmpty)
    #expect(!Command(number: 0, data: 0x3A).isEmpty)
}

@Test func commandCatalogMIDISide() {
    // Die fünf Stellen, an denen Tutka falsch liegt.
    #expect(CommandCatalog.midiEffect(0x05) == .controllerNumber)
    #expect(CommandCatalog.midiEffect(0x0A) == .polyphonicAftertouch)
    #expect(CommandCatalog.midiEffect(0x16) == .repeatRows)
    #expect(CommandCatalog.midiEffect(0x17) == .volumeController)
    #expect(CommandCatalog.midiEffect(0x1C) == .midiPreset)
}

@Test func tempoSpecials() {
    #expect(TempoSpecial(data: 0xFF) == .stopNote)
    #expect(TempoSpecial(data: 0xFE) == .stopSong)
    #expect(TempoSpecial(data: 0xF7) == .waitUntilSent)
    #expect(TempoSpecial(data: 0xFA) == .holdPedalOn)
    #expect(TempoSpecial(data: 0x40) == .setTempo(0x40))
}

@Test func volumeCommandAsMeasuredOnOriginal() {
    typealias C = CommandCatalog
    // Am Amiga gemessen (MIDI Monitor):
    // 0x00-0x40 skaliert, 0x41-0x7F ohne Wirkung, ab 0x80 Grundlautstaerke.
    #expect(C.volumeCommand(data: 0x40, encoding: .hexadecimal) == .velocity(127))
    #expect(C.volumeCommand(data: 0x41, encoding: .hexadecimal) == .ignored)
    #expect(C.volumeCommand(data: 0x7F, encoding: .hexadecimal) == .ignored)
    #expect(C.volumeCommand(data: 0x00, encoding: .hexadecimal) == .velocity(0))
    // Dieselben Patterndaten im Dezimalmodus: 0x40 bedeutet 40.
    #expect(C.volumeCommand(data: 0x40, encoding: .decimal) == .velocity(79))
    // Dezimal kann bis 99 reichen; darueber hinaus wirkungslos.
    #expect(C.volumeCommand(data: 0x64, encoding: .decimal) == .velocity(127))  // 64
    #expect(C.volumeCommand(data: 0x65, encoding: .decimal) == .ignored)        // 65
}

@Test func volumeScalingIsDoublingFromZero() {
    // Abgeschnitten gilt floor(v * 127/64) == 2v - 1 fuer v = 1...64.
    for v in 1...64 {
        #expect(CommandCatalog.volumeCommand(data: UInt8(v), encoding: .hexadecimal)
                == .velocity(UInt8(2 * v - 1)), "v = \(v)")
    }
}

@Test func sevenBitVolumeIsNotScaledOrLimited() {
    typealias C = CommandCatalog
    // Mit Befehlserweiterung ist der Wert bereits die Velocity — ohne die
    // 64er-Grenze, sonst waeren in den MMD3-Dateien drei Viertel aller
    // 0C-Befehle wirkungslos.
    #expect(C.volumeCommand(data: 0x40, encoding: .sevenBit) == .velocity(64))
    #expect(C.volumeCommand(data: 0x70, encoding: .sevenBit) == .velocity(112))
    #expect(C.volumeCommand(data: 0x7F, encoding: .sevenBit) == .velocity(127))
}

@Test func valuesFrom80SetDefaultVolume() {
    typealias C = CommandCatalog
    // Handbuch: "Range: 0-64, or $80-$C0 for default instrument volume."
    // Vom Autor bestaetigt: 0C90 ergibt Grundlautstaerke 16.
    #expect(C.volumeCommand(data: 0x90, encoding: .hexadecimal) == .setDefaultVolume(16))
    #expect(C.volumeCommand(data: 0x80, encoding: .hexadecimal) == .setDefaultVolume(0))
    #expect(C.volumeCommand(data: 0xC0, encoding: .hexadecimal) == .setDefaultVolume(64))
    #expect(C.volumeCommand(data: 0xC1, encoding: .hexadecimal) == .ignored)
    // Bit 7 wird vor der Lesart geprueft — auch im 7-Bit-Fall.
    #expect(C.volumeCommand(data: 0x90, encoding: .sevenBit) == .setDefaultVolume(16))
}

@Test func timingMatchesTheOriginal() throws {
    // BPM-Modus: am Tempo-Fenster von OctaMED bestaetigt —
    // O_Wie_Eine_Marionette.MMD zeigt dort Tempo 066, TPL 005, LPB 015.
    guard let url = TestFiles.file("O_Wie_Eine_Marionette.MMD") else { return }
    let song = try MEDLoader.load(file: url)
    #expect(song.bpmMode)
    #expect(song.defaultTempo == 66)
    #expect(song.ticksPerRow == 5)
    #expect(song.rowsPerBeat == 15)
    let row = try #require(Timing.rowDuration(song: song))
    #expect(abs(row - 60.0 / (66.0 * 15.0)) < 1e-9)
}

@Test func spdTimingFollowsTheCIATimer() {
    // SPD-Modus, Tempo 33 (Vorgabe eines neuen Songs): die Playroutine setzt
    // die CIA-Periode auf 470000/33 = 14242, bei 709379 Hz also 49,81 Ticks
    // je Sekunde — die klassischen 50 Hz.
    let period = (470_000.0 / 33.0).rounded(.down)
    let tick = period / Timing.ciaClockPAL
    #expect(abs(tick - 0.020077) < 1e-5)
    // Am Original gemessen: hold 1 gegen hold 32 ergab 0,620 s Unterschied.
    #expect(abs(31 * tick - 0.620) < 0.005)
}

@Test func svolToMIDI() {
    // Belegt am undokumentierten InstrExt-Feld der 24-Byte-Variante.
    #expect(CommandCatalog.midiVolume(ausSvol: 47) == 94)
    #expect(CommandCatalog.midiVolume(ausSvol: 64) == 127)
    #expect(CommandCatalog.midiVolume(ausSvol: 32) == 64)
}

@Test func shortFileIsRejected() {
    #expect(throws: MEDError.self) { try MEDLoader.load(bytes: [0x4D, 0x4D, 0x44, 0x31]) }
}

@Test func wrongSignatureIsRejected() {
    let bytes = [UInt8](repeating: 0, count: 100)
    #expect(throws: MEDError.self) { try MEDLoader.load(bytes: bytes) }
}

// MARK: - Gegen die echten Dateien

@Test func allTestFilesLoadAndModlenMatches() throws {
    let files = TestFiles.all
    guard !files.isEmpty else { return }   // songs/ fehlt — nichts zu prüfen
    for url in files {
        let song = try MEDLoader.load(file: url)
        // modlen ist die eingebaute Selbstprüfung des Formats.
        #expect(Int(song.modlen) == song.fileSize,
                "\(url.lastPathComponent): modlen \(song.modlen) != \(song.fileSize)")
        #expect(!song.blocks.isEmpty)
    }
}

@Test func noUnknownCommandsInTestFiles() throws {
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let unknown = song.diagnostics.commandCounts.keys.filter {
            CommandCatalog.midiEffect($0) == .unknown
        }.sorted()
        let list = unknown.map { String(format: "%02X", $0) }.joined(separator: ", ")
        #expect(unknown.isEmpty, "\(url.lastPathComponent): unbekannte Befehle \(list)")
    }
}

@Test func noChannelCollisionOfSoundingInstruments() throws {
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let collisions = song.diagnostics.warnings.filter {
            if case .channelCollision = $0.art { return true }
            return false
        }
        #expect(collisions.isEmpty, "\(url.lastPathComponent): \(collisions)")
    }
}

/// Die wichtigste Probe: gegen ein Bildschirmfoto aus OctaMED SoundStudio
/// V1.03c auf dem Amiga. Vorlage in docs/01-quellen-und-befunde.md.
@Test func patternViewMatchesOctaMED() throws {
    guard let url = TestFiles.file("O_Wie_Eine_Marionette.MMD") else { return }
    let song = try MEDLoader.load(file: url)
    let block = song.blocks[4]

    #expect(block.tracks == 20)
    #expect(block.rows == 512)

    let expected = """
    000   E-5 A0000 C-4 A0000 C-6 A0C00 C#6 10C50 --- 00000 --- 00000 --- 00905 C-7 10C00 C#6 20C6F C#5 20C6F
    001   --- 00000 --- 00000 --- 01758 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177F --- 00000 --- 00000
    002   --- 00000 --- 00000 --- 01758 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177F --- 00000 --- 00000
    003   --- 00000 --- 00000 --- 01758 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177F --- 00000 --- 00000
    004   G#4 A0000 B-3 A0000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
    005   --- 00000 --- 00000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
    006   --- 00000 --- 00000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
    007   --- 00000 --- 00000 --- 01757 --- 00000 --- 00000 --- 00000 --- 00000 --- 0177E --- 00000 --- 00000
    008   D#5 A0000 F#5 A0000 --- 01757 --- 00000 C#8 10C40 E-8 10C40 D#8 10C40 --- 0177D --- 00000 --- 00000
    """
    let actual = PatternRendering.block(block, rows: 0..<9, tracks: 0..<10)
    #expect(actual == expected)
}

/// Der spurbezogene Kanalzustand, an dem Block belegt.
@Test func command17ResolvesPerTrackToDifferentChannels() throws {
    guard let url = TestFiles.file("O_Wie_Eine_Marionette.MMD") else { return }
    let song = try MEDLoader.load(file: url)
    let block = song.blocks[4]

    var lastInstrument: [Int: UInt8] = [:]
    var hits: [(track: Int, channel: UInt8, value: UInt8)] = []
    for row in 0...1 {
        for track in 0..<block.tracks {
            let z = block.cell(row: row, track: track)
            if z.instrument != 0 { lastInstrument[track] = z.instrument }
            if row == 1, z.command.number == 0x17, let ins = lastInstrument[track] {
                let channel = song.instruments[Int(ins) - 1].midiChannel
                hits.append((track, channel, z.command.data))
            }
        }
    }
    #expect(hits.count == 4)
    #expect(Set(hits.map(\.channel)) == [10, 1, 2, 3])
    #expect(Set(hits.map(\.value)) == [0x58, 0x7F, 0x70])
}

@Test func dumpSplitsIntoIndividualSysExMessages() throws {
    guard let url = TestFiles.file("N_WOISTDAS_MU80.med") else { return }
    let song = try MEDLoader.load(file: url)
    let dump = try #require(song.dumps.first)
    #expect(dump.rawData.count == 13154)
    #expect(dump.isComplete)
    #expect(dump.manufacturer == 0x43)              // Yamaha
    #expect(dump.messages.count == 408)
    // Die letzte Nachricht trägt die MU80-eigene Model-ID 0x49, nicht XG 0x4C.
    let letzte = try #require(dump.messages.last)
    #expect(letzte[letzte.startIndex + 3] == 0x49)
}

@Test func instrExtSizeIsRespected() throws {
    // sehnsuchts_blues hat 10 Bytes je Eintrag. Das deckt long_midi_preset
    // (Offset 6, 2 Bytes) noch ab, das undokumentierte Feld bei Offset 18
    // dagegen nicht.
    if let url = TestFiles.file("sehnsuchts_blues.MMD1.pp") {
        let song = try MEDLoader.load(file: url)
        #expect(song.instruments.allSatisfy { $0.longPreset != nil })
        #expect(song.instruments.allSatisfy { $0.midiVolume == nil })
        // Ohne das Feld wird aus svol gerechnet.
        if let bass = song.instruments.first(where: { $0.name == "Bass" }) {
            #expect(bass.defaultVolume == 50)
            #expect(bass.initialMIDIVolume == 100)
        }
    }
    // N_WOISTDAS hat 24 Bytes — das undokumentierte MIDI-Lautstärkefeld ist da.
    if let url = TestFiles.file("N_WOISTDAS_MU80.med") {
        let song = try MEDLoader.load(file: url)
        let first = try #require(song.instruments.first)
        #expect(first.midiVolume == 94)      // svol 47
        #expect(first.defaultVolume == 47)
    }
}
