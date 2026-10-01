import Foundation

/// Liest MMD0–MMD3. Verändert nie eine Datei.
///
/// Leitquellen:
/// - Struktur: MMD_FileFormat.doc Rev. 6 (Teijo Kinnunen)
/// - Versionsunterschiede: zusätzlich OpenMPT `soundlib/Load_med.cpp`
/// - Befehlsbedeutung: OctaMED-SoundStudio-Handbuch, Anhang A
public enum MEDLoader {

    public static func lade(datei url: URL) throws -> Song {
        let daten = try Data(contentsOf: url)
        return try lade(bytes: [UInt8](daten), dateiname: url.lastPathComponent)
    }

    public static func lade(bytes: [UInt8], dateiname: String = "") throws -> Song {
        let r = ByteReader(bytes)
        guard r.passt(0, Layout.Modul.größe) else {
            throw MEDError.zuKurz(benötigt: Layout.Modul.größe, vorhanden: r.count)
        }

        let kennung = try r.u32(Layout.Modul.id)
        guard let version = MMDVersion(kennung: kennung) else {
            throw MEDError.keineMMDKennung(gefunden: r.textFest(0, länge: 4))
        }

        var warnungen: [Warnung] = []
        var hinweise: [Hinweis] = []

        // modlen taugt als Selbstprüfung: stimmt bei allen Testdateien exakt.
        let modlen = try r.u32(Layout.Modul.modlen)
        if Int(modlen) != r.count {
            warnungen.append(Warnung(
                art: .modlenStimmtNicht(modlen: modlen, dateigröße: r.count),
                fundstellen: [], anzahl: 1))
        }

        guard let songOffset = try r.zeiger(Layout.Modul.song, feld: "song") else {
            throw MEDError.strukturUnvollständig(feld: "song (Pflichtzeiger ist null)",
                                                 offset: Layout.Modul.song)
        }
        let blockarr = try r.zeiger(Layout.Modul.blockarr, feld: "blockarr")
        let smplarr = try r.zeiger(Layout.Modul.smplarr, feld: "smplarr")
        let expOffset = try r.zeiger(Layout.Modul.expdata, feld: "expdata")

        // --- Songkopf (gemeinsame Felder ab 504 bzw. 764) -------------------
        let anzahlBlöcke = Int(try r.u16(songOffset + Layout.Song.numblocks))
        let songlen = Int(try r.u16(songOffset + Layout.Song.songlen))
        let standardTempo = try r.u16(songOffset + Layout.Song.deftempo)
        let songTransponierung = try r.i8(songOffset + Layout.Song.playtransp)
        let flags = try r.u8(songOffset + Layout.Song.flags)
        let flags2 = try r.u8(songOffset + Layout.Song.flags2)
        let tempo2 = try r.u8(songOffset + Layout.Song.tempo2)
        let anzahlInstrumente = Int(try r.u8(songOffset + Layout.Song.numsamples))

        // FLAG2_BMASK = Bits 0–4, "0 = 1 line" -> +1
        let zeilenProBeat = Int(flags2 & 0x1F) + 1
        let bpmModus = flags2 & 0x20 != 0
        let mixingModus = flags2 & 0x80 != 0
        let lautstärkeHex = flags & 0x10 != 0   // FLAG_VOLHEX

        // --- Erweiterungsstruktur -------------------------------------------
        var songName = ""
        var instrExtOffset: Int?, instrExtGröße = 0, instrExtAnzahl = 0
        var iinfoOffset: Int?, iinfoGröße = 0, iinfoAnzahl = 0
        var dumps: [SysExDump] = []
        var cmd3x: [(typ: UInt8, nummer: UInt16)] = []

        if let e = expOffset {
            songName = r.text(try r.zeiger(e + Layout.Exp.songname, feld: "songname") ?? 0,
                              maxLänge: 128)
            instrExtOffset = try r.zeiger(e + Layout.Exp.expSmp, feld: "exp_smp")
            instrExtAnzahl = Int(try r.u16(e + Layout.Exp.sExtEntries))
            instrExtGröße = Int(try r.u16(e + Layout.Exp.sExtEntrsz))
            iinfoOffset = try r.zeiger(e + Layout.Exp.iinfo, feld: "iinfo")
            iinfoAnzahl = Int(try r.u16(e + Layout.Exp.iExtEntries))
            iinfoGröße = Int(try r.u16(e + Layout.Exp.iExtEntrsz))

            if instrExtGröße != 0 && instrExtGröße != 18 {
                warnungen.append(Warnung(
                    art: .instrExtUngewöhnlich(größe: UInt16(instrExtGröße)),
                    fundstellen: [], anzahl: 1))
            }
            dumps = try leseDumps(r, e, &warnungen)
            cmd3x = try leseCmd3x(r, e)
        }

        // --- Instrumente -----------------------------------------------------
        // Spezifikation: "IMPORTANT: If you are reading MMD3 modules, this
        // value may be greater than 63! You should ignore any exp_smp
        // structures above 63 in that case!"
        let instrExtNutzbar = min(instrExtAnzahl, 63)
        var instrumente: [Instrument] = []
        for i in 0..<anzahlInstrumente {
            let s = songOffset + Layout.Song.sample + i * Layout.Sample.größe
            guard r.passt(s, Layout.Sample.größe) else { break }

            var hold: UInt8?, decay: UInt8?, unterdrücken: Bool?
            var langesPreset: UInt16?, midiLautstärke: UInt8?
            if let x = instrExtOffset, instrExtGröße > 0, i < instrExtNutzbar {
                let o = x + i * instrExtGröße
                // Jedes Feld nur lesen, wenn die Eintragsgröße es abdeckt.
                if instrExtGröße > Layout.InstrExt.hold { hold = try r.u8(o + Layout.InstrExt.hold) }
                if instrExtGröße > Layout.InstrExt.decay { decay = try r.u8(o + Layout.InstrExt.decay) }
                if instrExtGröße > Layout.InstrExt.suppressMidiOff {
                    unterdrücken = try r.u8(o + Layout.InstrExt.suppressMidiOff) != 0
                }
                if instrExtGröße >= Layout.InstrExt.longMidiPreset + 2 {
                    langesPreset = try r.u16(o + Layout.InstrExt.longMidiPreset)
                }
                if instrExtGröße > Layout.InstrExt.midiLautstärke {
                    midiLautstärke = try r.u8(o + Layout.InstrExt.midiLautstärke)
                }
            }

            var name = ""
            if let x = iinfoOffset, iinfoGröße > 0, i < iinfoAnzahl {
                name = r.textFest(x + i * iinfoGröße, länge: min(40, iinfoGröße))
            }

            var hatSample = false
            if let sa = smplarr, r.passt(sa + i * 4, 4) {
                hatSample = (try r.zeiger(sa + i * 4, feld: "smplarr[\(i)]")) != nil
            }

            instrumente.append(Instrument(
                nummer: i + 1, name: name,
                midiKanal: try r.u8(s + Layout.Sample.midich),
                midiPreset: try r.u8(s + Layout.Sample.midipreset),
                langesPreset: langesPreset,
                standardLautstärke: try r.u8(s + Layout.Sample.svol),
                transponierung: try r.i8(s + Layout.Sample.strans),
                hold: hold, decay: decay, noteOffUnterdrücken: unterdrücken,
                midiLautstärke: midiLautstärke, hatSampleDaten: hatSample))
        }

        // --- Blöcke ----------------------------------------------------------
        var blöcke: [Block] = []
        if let ba = blockarr {
            for b in 0..<anzahlBlöcke {
                guard let bp = try r.zeiger(ba + b * 4, feld: "blockarr[\(b)]") else {
                    // Nullzeiger ist zulässig: Block existiert nicht.
                    blöcke.append(Block(nummer: b, name: "", spuren: 0, zeilen: 0,
                                        zellen: [], zusatzSeiten: []))
                    continue
                }
                blöcke.append(try leseBlock(r, bp, nummer: b, version: version))
            }
        }

        // --- Playsequenzen und Sections --------------------------------------
        var playsequenzen: [Playsequenz] = []
        var sections: [Int] = []
        if version.hatSections {
            let numpseqs = Int(try r.u16(songOffset + Layout.Song.numpseqs))
            if let pt = try r.zeiger(songOffset + Layout.Song.playseqtable, feld: "playseqtable") {
                for i in 0..<numpseqs {
                    guard let p = try r.zeiger(pt + i * 4, feld: "playseq[\(i)]") else { continue }
                    let länge = Int(try r.u16(p + Layout.PlaySeq.length))
                    var folge: [Int] = []
                    for j in 0..<länge {
                        let wert = try r.u16(p + Layout.PlaySeq.seqAb + j * 2)
                        // Spezifikation: Werte > 0x7FFF sind reserviert und
                        // werden von den Player-Routinen übersprungen.
                        if wert <= 0x7FFF { folge.append(Int(wert)) }
                    }
                    playsequenzen.append(Playsequenz(
                        name: r.textFest(p + Layout.PlaySeq.name, länge: Layout.PlaySeq.nameLänge),
                        blöcke: folge))
                }
            }
            if let st = try r.zeiger(songOffset + Layout.Song.sectiontable, feld: "sectiontable") {
                for i in 0..<songlen { sections.append(Int(try r.u16(st + i * 2))) }
            }
        } else {
            var folge: [Int] = []
            for i in 0..<songlen {
                folge.append(Int(try r.u8(songOffset + Layout.Song.playseq + i)))
            }
            playsequenzen = [Playsequenz(name: "", blöcke: folge)]
        }

        // --- Diagnose ---------------------------------------------------------
        var diagnose = Diagnose(warnungen: warnungen, hinweise: hinweise,
                                befehlsStatistik: [:], befehlsFundstellen: [:])
        werteAus(blöcke: blöcke, instrumente: instrumente, cmd3x: cmd3x,
                 lautstärkeHex: lautstärkeHex, in: &diagnose)
        hinweise = diagnose.hinweise

        return Song(
            version: version, name: songName, dateiname: dateiname,
            modlen: modlen, dateigröße: r.count,
            weitereSongs: Int(try r.u8(Layout.Modul.extraSongs)),
            standardTempo: standardTempo, ticksProZeile: tempo2,
            bpmModus: bpmModus, zeilenProBeat: zeilenProBeat,
            songTransponierung: songTransponierung, mixingModus: mixingModus,
            lautstärkeHex: lautstärkeHex,
            instrumente: instrumente, blöcke: blöcke,
            playsequenzen: playsequenzen, sections: sections,
            dumps: dumps, cmd3xController: cmd3x, diagnose: diagnose)
    }

    // MARK: - Blöcke

    private static func leseBlock(_ r: ByteReader, _ bp: Int,
                                  nummer: Int, version: MMDVersion) throws -> Block {
        let spuren: Int, zeilen: Int
        var name = ""
        var zusatzSeiten: [[Befehl]] = []

        if version == .mmd0 {
            spuren = Int(try r.u8(bp))
            zeilen = Int(try r.u8(bp + 1)) + 1        // "0 = 1 line"
        } else {
            spuren = Int(try r.u16(bp))
            zeilen = Int(try r.u16(bp + 2)) + 1
            if let info = try r.zeiger(bp + 4, feld: "BlockInfo") {
                if let bn = try r.zeiger(info + Layout.BlockInfo.blockname, feld: "blockname") {
                    let länge = Int(try r.u32(info + Layout.BlockInfo.blocknamelen))
                    name = r.text(bn, maxLänge: max(1, min(länge, 256)))
                }
                if let pt = try r.zeiger(info + Layout.BlockInfo.pagetable, feld: "pagetable") {
                    let seiten = Int(try r.u16(pt))
                    for s in 0..<seiten {
                        guard let sp = try r.zeiger(pt + 4 + s * 4, feld: "page[\(s)]") else { continue }
                        var befehle: [Befehl] = []
                        befehle.reserveCapacity(spuren * zeilen)
                        for i in 0..<(spuren * zeilen) {
                            let o = sp + i * 2
                            guard r.passt(o, 2) else { break }
                            befehle.append(Befehl(nummer: try r.u8(o), daten: try r.u8(o + 1)))
                        }
                        zusatzSeiten.append(befehle)
                    }
                }
            }
        }

        let basis = bp + version.blockKopfBytes
        let schritt = version.notenBytes
        var zellen: [Zelle] = []
        zellen.reserveCapacity(spuren * zeilen)

        for i in 0..<(spuren * zeilen) {
            let o = basis + i * schritt
            guard r.passt(o, schritt) else { zellen.append(.leer); continue }
            if version == .mmd0 {
                // xynnnnnn iiiicccc dddddddd
                // x = Instrumentbit 4, y = Instrumentbit 5
                let b0 = try r.u8(o), b1 = try r.u8(o + 1), b2 = try r.u8(o + 2)
                let instrument = (b1 >> 4) | ((b0 & 0x80) >> 3) | ((b0 & 0x40) >> 1)
                zellen.append(Zelle(note: b0 & 0x3F, instrument: instrument,
                                    befehl: Befehl(nummer: b1 & 0x0F, daten: b2)))
            } else {
                // xnnnnnnn xxiiiiii cccccccc dddddddd
                // Die x-Bits MÜSSEN beim Lesen ausmaskiert werden.
                zellen.append(Zelle(note: try r.u8(o) & 0x7F,
                                    instrument: try r.u8(o + 1) & 0x3F,
                                    befehl: Befehl(nummer: try r.u8(o + 2),
                                                   daten: try r.u8(o + 3))))
            }
        }
        return Block(nummer: nummer, name: name, spuren: spuren, zeilen: zeilen,
                     zellen: zellen, zusatzSeiten: zusatzSeiten)
    }

    // MARK: - Dumps und Cmd3x

    private static func leseDumps(_ r: ByteReader, _ e: Int,
                                  _ warnungen: inout [Warnung]) throws -> [SysExDump] {
        guard let dd = try r.zeiger(e + Layout.Exp.dumps, feld: "dumps") else { return [] }
        let anzahl = Int(try r.u16(dd + Layout.DumpData.numdumps))
        var ergebnis: [SysExDump] = []
        for i in 0..<anzahl {
            guard let dp = try r.zeiger(dd + Layout.DumpData.zeigerAb + i * 4,
                                        feld: "dump[\(i)]") else { continue }
            let länge = Int(try r.u32(dp + Layout.Dump.length))
            let extLen = Int(try r.u16(dp + Layout.Dump.extLen))
            let name = extLen >= Layout.Dump.nameLänge
                ? r.textFest(dp + Layout.Dump.name, länge: Layout.Dump.nameLänge) : ""
            var roh: [UInt8] = []
            if let dz = try r.zeiger(dp + Layout.Dump.data, feld: "dump[\(i)].data"),
               r.passt(dz, länge) {
                roh = Array(r.bytes[dz..<(dz + länge)])
            }
            let dump = SysExDump(index: i, name: name, rohdaten: roh)
            if !roh.isEmpty && !dump.istVollständig {
                warnungen.append(Warnung(art: .dumpUnvollständig(index: i),
                                         fundstellen: [], anzahl: 1))
            }
            ergebnis.append(dump)
        }
        return ergebnis
    }

    private static func leseCmd3x(_ r: ByteReader, _ e: Int) throws
        -> [(typ: UInt8, nummer: UInt16)] {
        guard let c = try r.zeiger(e + Layout.Exp.mmdcmd3x, feld: "mmdcmd3x") else { return [] }
        let anzahl = Int(try r.u16(c + Layout.Cmd3x.numOfSettings))
        guard let typen = try r.zeiger(c + Layout.Cmd3x.ctrlrTypes, feld: "ctrlr_types"),
              let nummern = try r.zeiger(c + Layout.Cmd3x.ctrlrNumbers, feld: "ctrlr_numbers")
        else { return [] }
        var ergebnis: [(typ: UInt8, nummer: UInt16)] = []
        for i in 0..<anzahl {
            guard r.passt(typen + i, 1), r.passt(nummern + i * 2, 2) else { break }
            ergebnis.append((typ: try r.u8(typen + i), nummer: try r.u16(nummern + i * 2)))
        }
        return ergebnis
    }
}
