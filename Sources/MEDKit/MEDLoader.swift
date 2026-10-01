import Foundation

/// Liest MMD0–MMD3. Verändert nie eine Datei.
///
/// Leitquellen:
/// - Struktur: MMD_FileFormat.doc Rev. 6 (Teijo Kinnunen)
/// - Versionsunterschiede: zusätzlich OpenMPT `soundlib/Load_med.cpp`
/// - Befehlsbedeutung: OctaMED-SoundStudio-Handbuch, Anhang A
public enum MEDLoader {

    public static func load(file url: URL) throws -> Song {
        let data = try Data(contentsOf: url)
        return try load(bytes: [UInt8](data), fileName: url.lastPathComponent)
    }

    public static func load(bytes: [UInt8], fileName: String = "") throws -> Song {
        let r = ByteReader(bytes)
        guard r.fits(0, Layout.Module.size) else {
            throw MEDError.tooShort(needed: Layout.Module.size, available: r.count)
        }

        let signature = try r.u32(Layout.Module.id)
        guard let version = MMDVersion(signature: signature) else {
            throw MEDError.noMMDSignature(gefunden: r.fixedString(0, length: 4))
        }

        var warnings: [Warning] = []
        var notices: [Notice] = []

        // modlen taugt als Selbstprüfung: stimmt bei allen Testdateien exakt.
        let modlen = try r.u32(Layout.Module.modlen)
        if Int(modlen) != r.count {
            warnings.append(Warning(
                art: .modlenMismatch(modlen: modlen, fileSize: r.count),
                locations: [], count: 1))
        }

        guard let songOffset = try r.pointer(Layout.Module.song, field: "song") else {
            throw MEDError.truncatedStructure(field: "song (Pflichtzeiger ist null)",
                                                 offset: Layout.Module.song)
        }
        let blockarr = try r.pointer(Layout.Module.blockarr, field: "blockarr")
        let smplarr = try r.pointer(Layout.Module.smplarr, field: "smplarr")
        let expOffset = try r.pointer(Layout.Module.expdata, field: "expdata")

        // --- Songkopf (gemeinsame Felder ab 504 bzw. 764) -------------------
        let blockCount = Int(try r.u16(songOffset + Layout.Song.numblocks))
        let songlen = Int(try r.u16(songOffset + Layout.Song.songlen))
        let defaultTempo = try r.u16(songOffset + Layout.Song.deftempo)
        let songTranspose = try r.i8(songOffset + Layout.Song.playtransp)
        let flags = try r.u8(songOffset + Layout.Song.flags)
        let flags2 = try r.u8(songOffset + Layout.Song.flags2)
        let tempo2 = try r.u8(songOffset + Layout.Song.tempo2)
        let instrumentCount = Int(try r.u8(songOffset + Layout.Song.numsamples))

        // FLAG2_BMASK = Bits 0–4, "0 = 1 line" -> +1
        let rowsPerBeat = Int(flags2 & 0x1F) + 1
        let bpmMode = flags2 & 0x20 != 0
        let mixingMode = flags2 & 0x80 != 0
        let volumeIsHex = flags & 0x10 != 0   // FLAG_VOLHEX

        // --- Erweiterungsstruktur -------------------------------------------
        var songName = ""
        var instrExtOffset: Int?, instrExtSize = 0, instrExtAnzahl = 0
        var iinfoOffset: Int?, iinfoSize = 0, iinfoAnzahl = 0
        var dumps: [SysExDump] = []
        var cmd3x: [(typ: UInt8, number: UInt16)] = []

        if let e = expOffset {
            // Die Spezifikation gibt MMD0exp mit 84 Bytes an (letztes Feld
            // `tag_end`). Gemessen: alle drei MMD3-Dateien der Testsammlung
            // enden 4 Bytes davor — die Windows-Version schreibt die Struktur
            // verkuerzt. Da `modlen` genau der Dateigroesse entspricht, greift
            // ein Lader, der die vollen 84 Bytes liest, hinter das Modul.
            // Vermutlich der Grund, warum die Amiga-Version diese Dateien
            // ablehnt. Wir lesen `tag_end` ohnehin nicht.
            let available = r.count - e
            if available < Layout.Exp.size {
                warnings.append(Warning(
                    art: .other("Erweiterungsstruktur ist \(Layout.Exp.size - available) "
                        + "Bytes kürzer als dokumentiert (\(available) statt \(Layout.Exp.size)) "
                        + "— ältere OctaMED-Versionen können die Datei deshalb ablehnen"),
                    locations: [], count: 1))
            }
            songName = r.string(try r.pointer(e + Layout.Exp.songname, field: "songname") ?? 0,
                              maxLength: 128)
            instrExtOffset = try r.pointer(e + Layout.Exp.expSmp, field: "exp_smp")
            instrExtAnzahl = Int(try r.u16(e + Layout.Exp.sExtEntries))
            instrExtSize = Int(try r.u16(e + Layout.Exp.sExtEntrsz))
            iinfoOffset = try r.pointer(e + Layout.Exp.iinfo, field: "iinfo")
            iinfoAnzahl = Int(try r.u16(e + Layout.Exp.iExtEntries))
            iinfoSize = Int(try r.u16(e + Layout.Exp.iExtEntrsz))

            if instrExtSize != 0 && instrExtSize != 18 {
                warnings.append(Warning(
                    art: .unusualInstrExtSize(size: UInt16(instrExtSize)),
                    locations: [], count: 1))
            }
            dumps = try readDumps(r, e, &warnings)
            cmd3x = try readCmd3x(r, e)
        }

        // --- Instrumente -----------------------------------------------------
        // Spezifikation: "IMPORTANT: If you are reading MMD3 modules, this
        // value may be greater than 63! You should ignore any exp_smp
        // structures above 63 in that case!"
        let instrExtUsable = min(instrExtAnzahl, 63)
        var instruments: [Instrument] = []
        for i in 0..<instrumentCount {
            let s = songOffset + Layout.Song.sample + i * Layout.Sample.size
            guard r.fits(s, Layout.Sample.size) else { break }

            var hold: UInt8?, decay: UInt8?, suppress: Bool?
            var longPreset: UInt16?, midiVolume: UInt8?
            if let x = instrExtOffset, instrExtSize > 0, i < instrExtUsable {
                let o = x + i * instrExtSize
                // Jedes Feld nur lesen, wenn die Eintragsgröße es abdeckt.
                if instrExtSize > Layout.InstrExt.hold { hold = try r.u8(o + Layout.InstrExt.hold) }
                if instrExtSize > Layout.InstrExt.decay { decay = try r.u8(o + Layout.InstrExt.decay) }
                if instrExtSize > Layout.InstrExt.suppressMidiOff {
                    suppress = try r.u8(o + Layout.InstrExt.suppressMidiOff) != 0
                }
                if instrExtSize >= Layout.InstrExt.longMidiPreset + 2 {
                    longPreset = try r.u16(o + Layout.InstrExt.longMidiPreset)
                }
                if instrExtSize > Layout.InstrExt.midiVolume {
                    midiVolume = try r.u8(o + Layout.InstrExt.midiVolume)
                }
            }

            var name = ""
            if let x = iinfoOffset, iinfoSize > 0, i < iinfoAnzahl {
                name = r.fixedString(x + i * iinfoSize, length: min(40, iinfoSize))
            }

            var hatSample = false
            if let sa = smplarr, r.fits(sa + i * 4, 4) {
                hatSample = (try r.pointer(sa + i * 4, field: "smplarr[\(i)]")) != nil
            }

            instruments.append(Instrument(
                number: i + 1, name: name,
                midiChannel: try r.u8(s + Layout.Sample.midich),
                midiPreset: try r.u8(s + Layout.Sample.midipreset),
                longPreset: longPreset,
                defaultVolume: try r.u8(s + Layout.Sample.svol),
                transpose: try r.i8(s + Layout.Sample.strans),
                hold: hold, decay: decay, suppressNoteOff: suppress,
                midiVolume: midiVolume, hasSampleData: hatSample))
        }

        // --- Blöcke ----------------------------------------------------------
        var blocks: [Block] = []
        if let ba = blockarr {
            for b in 0..<blockCount {
                guard let bp = try r.pointer(ba + b * 4, field: "blockarr[\(b)]") else {
                    // Nullzeiger ist zulässig: Block existiert nicht.
                    blocks.append(Block(number: b, name: "", tracks: 0, rows: 0,
                                        cells: [], extraPages: []))
                    continue
                }
                blocks.append(try readBlock(r, bp, number: b, version: version))
            }
        }

        // --- Playsequenzen und Sections --------------------------------------
        var playSequences: [PlaySequence] = []
        var sections: [Int] = []
        if version.hasSections {
            let numpseqs = Int(try r.u16(songOffset + Layout.Song.numpseqs))
            if let pt = try r.pointer(songOffset + Layout.Song.playseqtable, field: "playseqtable") {
                for i in 0..<numpseqs {
                    guard let p = try r.pointer(pt + i * 4, field: "playseq[\(i)]") else { continue }
                    let length = Int(try r.u16(p + Layout.PlaySeq.length))
                    var order: [Int] = []
                    for j in 0..<length {
                        let value = try r.u16(p + Layout.PlaySeq.seqAb + j * 2)
                        // Spezifikation: Werte > 0x7FFF sind reserviert und
                        // werden von den Player-Routinen übersprungen.
                        if value <= 0x7FFF { order.append(Int(value)) }
                    }
                    playSequences.append(PlaySequence(
                        name: r.fixedString(p + Layout.PlaySeq.name, length: Layout.PlaySeq.nameLength),
                        blocks: order))
                }
            }
            if let st = try r.pointer(songOffset + Layout.Song.sectiontable, field: "sectiontable") {
                for i in 0..<songlen { sections.append(Int(try r.u16(st + i * 2))) }
            }
        } else {
            var order: [Int] = []
            for i in 0..<songlen {
                order.append(Int(try r.u8(songOffset + Layout.Song.playseq + i)))
            }
            playSequences = [PlaySequence(name: "", blocks: order)]
        }

        // --- Diagnose ---------------------------------------------------------
        var diagnostics = Diagnostics(warnings: warnings, notices: notices,
                                commandCounts: [:], commandLocations: [:])
        analyse(blocks: blocks, instruments: instruments, cmd3x: cmd3x,
                 volumeIsHex: volumeIsHex,
                 sevenBit: blocks.contains { $0.sevenBitVolume }, in: &diagnostics)
        notices = diagnostics.notices

        return Song(
            version: version, name: songName, fileName: fileName,
            modlen: modlen, fileSize: r.count,
            extraSongs: Int(try r.u8(Layout.Module.extraSongs)),
            defaultTempo: defaultTempo, ticksPerRow: tempo2,
            bpmMode: bpmMode, rowsPerBeat: rowsPerBeat,
            songTranspose: songTranspose, mixingMode: mixingMode,
            volumeIsHex: volumeIsHex,
            instruments: instruments, blocks: blocks,
            playSequences: playSequences, sections: sections,
            dumps: dumps, cmd3xControllers: cmd3x, diagnostics: diagnostics)
    }

    // MARK: - Blöcke

    private static func readBlock(_ r: ByteReader, _ bp: Int,
                                  number: Int, version: MMDVersion) throws -> Block {
        let tracks: Int, rows: Int
        var name = ""
        var extraPages: [[Command]] = []
        var extraParameters: [[UInt8]] = []

        if version == .mmd0 {
            tracks = Int(try r.u8(bp))
            rows = Int(try r.u8(bp + 1)) + 1        // "0 = 1 line"
        } else {
            tracks = Int(try r.u16(bp))
            rows = Int(try r.u16(bp + 2)) + 1
            if let info = try r.pointer(bp + 4, field: "BlockInfo") {
                if let bn = try r.pointer(info + Layout.BlockInfo.blockname, field: "blockname") {
                    let length = Int(try r.u32(info + Layout.BlockInfo.blocknamelen))
                    name = r.string(bn, maxLength: max(1, min(length, 256)))
                }
                // Befehlserweiterung: ein Byte je Zelle und Seite.
                if let ce = try r.pointer(info + Layout.BlockInfo.cmdExtTable,
                                         field: "cmdExtTable"),
                   let table = try r.pointer(ce, field: "cmdExtTable[0]") {
                    let totalPages = 1 + extraPageCount(r, info)
                    let perPage = tracks * rows
                    for s in 0..<totalPages {
                        let start = table + s * perPage
                        guard r.fits(start, perPage) else { break }
                        extraParameters.append(Array(r.bytes[start..<(start + perPage)]))
                    }
                }
                if let pt = try r.pointer(info + Layout.BlockInfo.pagetable, field: "pagetable") {
                    let pages = Int(try r.u16(pt))
                    for s in 0..<pages {
                        guard let sp = try r.pointer(pt + 4 + s * 4, field: "page[\(s)]") else { continue }
                        var commands: [Command] = []
                        commands.reserveCapacity(tracks * rows)
                        for i in 0..<(tracks * rows) {
                            let o = sp + i * 2
                            guard r.fits(o, 2) else { break }
                            commands.append(Command(number: try r.u8(o), data: try r.u8(o + 1)))
                        }
                        extraPages.append(commands)
                    }
                }
            }
        }

        let base = bp + version.blockHeaderBytes
        let stride = version.noteBytes
        var cells: [Cell] = []
        cells.reserveCapacity(tracks * rows)

        for i in 0..<(tracks * rows) {
            let o = base + i * stride
            guard r.fits(o, stride) else { cells.append(.empty); continue }
            if version == .mmd0 {
                // xynnnnnn iiiicccc dddddddd
                // x = Instrumentbit 4, y = Instrumentbit 5
                let b0 = try r.u8(o), b1 = try r.u8(o + 1), b2 = try r.u8(o + 2)
                let instrument = (b1 >> 4) | ((b0 & 0x80) >> 3) | ((b0 & 0x40) >> 1)
                cells.append(Cell(note: b0 & 0x3F, instrument: instrument,
                                    command: Command(number: b1 & 0x0F, data: b2)))
            } else {
                // xnnnnnnn xxiiiiii cccccccc dddddddd
                // Die x-Bits MÜSSEN beim Lesen ausmaskiert werden.
                cells.append(Cell(note: try r.u8(o) & 0x7F,
                                    instrument: try r.u8(o + 1) & 0x3F,
                                    command: Command(number: try r.u8(o + 2),
                                                   data: try r.u8(o + 3))))
            }
        }
        return Block(number: number, name: name, tracks: tracks, rows: rows,
                     cells: cells, extraPages: extraPages,
                     extraParameters: extraParameters)
    }

    /// Zahl der zusätzlichen Befehlsseiten laut `BlockCmdPageTable`.
    private static func extraPageCount(_ r: ByteReader, _ info: Int) -> Int {
        guard let pt = try? r.pointer(info + Layout.BlockInfo.pagetable, field: "pagetable"),
              let n = try? r.u16(pt) else { return 0 }
        return Int(n)
    }

    // MARK: - Dumps und Cmd3x

    private static func readDumps(_ r: ByteReader, _ e: Int,
                                  _ warnings: inout [Warning]) throws -> [SysExDump] {
        guard let dd = try r.pointer(e + Layout.Exp.dumps, field: "dumps") else { return [] }
        let count = Int(try r.u16(dd + Layout.DumpData.numdumps))
        var result: [SysExDump] = []
        for i in 0..<count {
            guard let dp = try r.pointer(dd + Layout.DumpData.zeigerAb + i * 4,
                                        field: "dump[\(i)]") else { continue }
            let length = Int(try r.u32(dp + Layout.Dump.length))
            let extLen = Int(try r.u16(dp + Layout.Dump.extLen))
            let name = extLen >= Layout.Dump.nameLength
                ? r.fixedString(dp + Layout.Dump.name, length: Layout.Dump.nameLength) : ""
            var raw: [UInt8] = []
            if let dz = try r.pointer(dp + Layout.Dump.data, field: "dump[\(i)].data"),
               r.fits(dz, length) {
                raw = Array(r.bytes[dz..<(dz + length)])
            }
            let dump = SysExDump(index: i, name: name, rawData: raw)
            if !raw.isEmpty && !dump.isComplete {
                warnings.append(Warning(art: .incompleteDump(index: i),
                                         locations: [], count: 1))
            }
            result.append(dump)
        }
        return result
    }

    private static func readCmd3x(_ r: ByteReader, _ e: Int) throws
        -> [(typ: UInt8, number: UInt16)] {
        guard let c = try r.pointer(e + Layout.Exp.mmdcmd3x, field: "mmdcmd3x") else { return [] }
        let count = Int(try r.u16(c + Layout.Cmd3x.numOfSettings))
        guard let types = try r.pointer(c + Layout.Cmd3x.ctrlrTypes, field: "ctrlr_types"),
              let numbers = try r.pointer(c + Layout.Cmd3x.ctrlrNumbers, field: "ctrlr_numbers")
        else { return [] }
        var result: [(typ: UInt8, number: UInt16)] = []
        for i in 0..<count {
            guard r.fits(types + i, 1), r.fits(numbers + i * 2, 2) else { break }
            result.append((typ: try r.u8(types + i), number: try r.u16(numbers + i * 2)))
        }
        return result
    }
}
