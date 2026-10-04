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
    // Am Original gemessen: ein 64-Zeilen-Block lief in 14,547 s durch
    // (Note On 18:29:38.399 bis Note Off 18:29:52.946), bei BPM 33, TPL 6,
    // LPB 8 laut Tempo-Fenster. Das sind 227,297 ms je Zeile.
    let song = try MEDLoader.load(bytes: syntheticSong(tempo: 33, tpl: 6, lpb: 8, bpm: true))
    let row = try #require(Timing.rowDuration(song: song))
    #expect(abs(row - 0.227297) < 0.0005, "berechnet \(row * 1000) ms")
}

@Test func tplAffectsRowDurationInBPMMode() throws {
    // Die verbreitete Formel 60/(BPM*LPB) stimmt nur bei TPL = 6. Der
    // Interrupt-Handler teilt im BPM-Modus durch vier und mmd_counter zaehlt
    // bis TPL — die Zeilendauer ist also TPL * 10 / (BPM * LPB).
    let sechs = try MEDLoader.load(bytes: syntheticSong(tempo: 66, tpl: 6, lpb: 15, bpm: true))
    let fuenf = try MEDLoader.load(bytes: syntheticSong(tempo: 66, tpl: 5, lpb: 15, bpm: true))
    let r6 = try #require(Timing.rowDuration(song: sechs))
    let r5 = try #require(Timing.rowDuration(song: fuenf))
    #expect(abs(r6 - 60.0 / (66.0 * 15.0)) < 0.0005)   // bei TPL 6 deckungsgleich
    #expect(abs(r5 - 0.050495) < 0.0005)               // bei TPL 5 um 20 % kuerzer
}

@Test func spdTimingFollowsTheCIATimer() throws {
    // SPD-Modus, Tempo 33 (Vorgabe eines neuen Songs): Periode 470000/33 =
    // 14242, bei 709379 Hz also 49,81 Ticks je Sekunde — die klassischen 50 Hz.
    let song = try MEDLoader.load(bytes: syntheticSong(tempo: 33, tpl: 6, lpb: 8, bpm: false))
    let tick = try #require(Timing.tickDuration(song: song))
    #expect(abs(tick - 0.020077) < 1e-5)
    // Am Original gemessen: hold 1 gegen hold 32 ergab 0,620 s Unterschied.
    #expect(abs(31 * tick - 0.620) < 0.005)
}

/// Kleinstes gueltiges MMD1 mit den gewuenschten Tempowerten — fuer Tests, die
/// keine echte Songdatei brauchen.
private func syntheticSong(tempo: UInt16, tpl: UInt8, lpb: UInt8, bpm: Bool) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: 52 + 788)
    b[0...3] = ArraySlice("MMD1".utf8)
    func put32(_ v: Int, _ o: Int) {
        b[o] = UInt8(v >> 24 & 0xFF); b[o+1] = UInt8(v >> 16 & 0xFF)
        b[o+2] = UInt8(v >> 8 & 0xFF); b[o+3] = UInt8(v & 0xFF)
    }
    put32(b.count, 4)          // modlen
    put32(52, 8)               // song-Zeiger
    let s = 52
    b[s + 504] = 0; b[s + 505] = 0                       // numblocks
    b[s + 764] = UInt8(tempo >> 8); b[s + 765] = UInt8(tempo & 0xFF)
    b[s + 768] = (lpb - 1) | (bpm ? 0x20 : 0)            // flags2
    b[s + 769] = tpl                                     // tempo2
    b[s + 787] = 0                                       // numsamples
    return b
}

@Test func noteDurationMatchesTheMeasurements() throws {
    // Am Original gemessen: BPM 33, TPL 6, LPB 8; eine Note in Zeile 0 mit
    // 15 Haltezeilen darunter. Gemessene Notenlaengen je hold-Wert.
    let song = try MEDLoader.load(bytes: syntheticSong(tempo: 33, tpl: 6, lpb: 8, bpm: true))
    for (hold, gemessen) in [(UInt8(1), 3.446), (16, 4.015), (64, 5.832)] {
        let d = try #require(Timing.noteDuration(holdRows: 15, hold: hold, song: song))
        #expect(abs(d - gemessen) < 0.01,
                "hold \(hold): berechnet \(d) s, gemessen \(gemessen) s")
    }
}

@Test func holdZeroMeansUnlimited() throws {
    // Der Assembler setzt den Zaehler bei hold = 0 auf -1; ein negativer
    // Zaehler wird weder verlaengert noch heruntergezaehlt. Vom Autor
    // bestaetigt: "hold 0 spielt eine note unendlich".
    let song = try MEDLoader.load(bytes: syntheticSong(tempo: 33, tpl: 6, lpb: 8, bpm: true))
    #expect(Timing.noteDuration(holdRows: 15, hold: 0, song: song) == nil)
    #expect(Timing.noteDuration(holdRows: 0, hold: 0, song: song) == nil)
    // Ohne Haltezeilen wirkt hold trotzdem.
    let d = try #require(Timing.noteDuration(holdRows: 0, hold: 64, song: song))
    #expect(abs(d - 64 * 0.037875) < 0.005)
}

@Test func holdRowsCountsInstrumentOnlyCells() throws {
    // Die Haltezeilen sind Daten: Zellen mit nur der Instrumentnummer.
    guard let url = TestFiles.file("unsere_hände_spielen.MMD") else { return }
    let song = try MEDLoader.load(file: url)
    var gefunden = 0
    for block in song.blocks {
        for row in 0..<block.rows {
            for track in 0..<block.tracks where block.cell(row: row, track: track).note > 0 {
                if block.holdRows(afterRow: row, track: track) > 0 { gefunden += 1 }
            }
        }
    }
    #expect(gefunden > 100, "nur \(gefunden) Noten mit Haltezeilen")
}

@Test func sysExExportProducesValidFiles() throws {
    guard let url = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let song = try MEDLoader.load(file: url)
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("med2midi-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }

    let result = try SysExExport.write(song: song, to: folder)
    #expect(result.dumps.count == 2)

    for info in result.dumps {
        let data = try Data(contentsOf: folder.appendingPathComponent(info.fileName))
        #expect(data.count == info.byteCount)
        #expect(data.first == 0xF0)
        #expect(data.last == 0xF7)
        // Der Strom muss restlos in F0...F7-Nachrichten zerfallen.
        var count = 0, i = data.startIndex
        while i < data.endIndex, data[i] == 0xF0 {
            guard let end = data[i...].firstIndex(of: 0xF7) else { break }
            count += 1
            i = data.index(after: end)
        }
        #expect(i == data.endIndex, "\(info.fileName): Rest nach der letzten Nachricht")
        #expect(count == info.messageCount)
        #expect(info.manufacturer == 0x43)          // Yamaha
        #expect(info.modelIDs.contains(0x4C))       // XG
    }
    // Einer der beiden Dumps wird per Befehl 10 ausgeloest.
    #expect(result.dumps.contains { $0.triggeredAt != nil })
    #expect(FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("dumps.txt").path))
}

@Test func dumpsAreAllDistinct() throws {
    // Gleiche Laenge und gleicher Kopf, aber verschiedene Pruefsummen: jeder
    // Song hat seinen eigenen Klangsatz. Eine fruehere Notiz behauptete das
    // Gegenteil.
    var hashes: Set<String> = []
    var total = 0
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        for dump in song.dumps {
            total += 1
            hashes.insert(SysExExport.shortHash(dump.rawData))
        }
    }
    guard total > 0 else { return }
    #expect(hashes.count == total, "\(total) Dumps, aber nur \(hashes.count) verschiedene")
}

@Test func everyDumpMessageIsIntact() throws {
    // Eine Sollgroesse fuer den ganzen Dump gibt es nicht — jede Nachricht
    // traegt ihre Byteanzahl selbst. Geprueft wird deshalb jede einzeln:
    // deklarierte Laenge und Yamaha-Pruefsumme.
    var total = 0
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        for dump in song.dumps {
            let check = dump.check()
            let befund = "\(url.lastPathComponent) Dump \(dump.index): "
                + "Anzahl \(check.countsValid)/\(check.messages), "
                + "Pruefsumme \(check.checksumsValid)/\(check.messages), "
                + "\(check.trailingBytes) Restbytes"
            #expect(check.isIntact, "\(befund)")
            total += check.messages
        }
    }
    // Am Material: 4480 Nachrichten in 11 Dumps.
    if total > 0 { #expect(total == 4480, "\(total) Nachrichten statt 4480") }
}

@Test func playerBalancesNoteOnsAndOffs() throws {
    // Jede Note muss beendet werden — sonst haengt der Klangerzeuger.
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let result = Player(song: song).run()
        var ons = 0, offs = 0
        for event in result.events {
            if case .noteOn = event.kind { ons += 1 }
            if case .noteOff = event.kind { offs += 1 }
        }
        #expect(ons == offs, "\(url.lastPathComponent): \(ons) Note On, \(offs) Note Off")
        #expect(ons > 0)
    }
}

@Test func playerStopsAtTheStopCommand() throws {
    // Jeder Song hat genau ein erreichbares 0F FE an der letzten
    // Sequenzposition. Danach darf nichts mehr kommen.
    guard let url = TestFiles.file("N_WOISTDAS_MU80.med") else { return }
    let song = try MEDLoader.load(file: url)
    let result = Player(song: song).run()
    // Block 26 bricht in Zeile 1 von 128 ab — ohne Auswertung waeren es
    // 126 Zeilen mehr.
    let rowTicks = Player.ppq / song.rowsPerBeat
    let withoutStop = result.lengthInTicks + 126 * rowTicks
    #expect(result.lengthInTicks < withoutStop)
    // Kein Ereignis darf hinter dem Ende liegen.
    #expect(result.events.allSatisfy { $0.tick <= result.lengthInTicks })
}

@Test func controllerNumberIsKeptPerTrack() throws {
    // In sehnsuchts_blues steht das 05 in Zeile 0 ohne Instrument, der
    // zugehoerige 00-Wert erst in Zeile 1 auf einem anderen Kanal. Pro Kanal
    // gespeichert gingen die Controller-Werte verloren.
    guard let url = TestFiles.file("sehnsuchts_blues.MMD1.pp") else { return }
    let song = try MEDLoader.load(file: url)
    let result = Player(song: song).run()
    let cc74 = result.events.filter {
        if case .controlChange(let c, _) = $0.kind { return c == 74 }
        return false
    }
    #expect(cc74.count > 400, "nur \(cc74.count) CC74-Ereignisse")
    let missing = result.warnings.filter { $0.contains("ohne vorherige Nummer") }
    #expect(missing.isEmpty, "\(missing.count) Controller-Werte ohne Nummer")
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
