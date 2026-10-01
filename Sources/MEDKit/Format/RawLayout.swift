import Foundation

/// Feste Offsets der MMD-Strukturen.
///
/// Alle Werte aus MMD_FileFormat.doc Rev. 6 (Teijo Kinnunen), wo die Offsets
/// im Kommentar `/* n */` jeder Strukturzeile stehen.
enum Layout {
    /// `struct MMD0` — 52 Bytes.
    enum Module {
        static let id = 0, modlen = 4, song = 8, blockarr = 16
        static let mmdflags = 20, smplarr = 24, expdata = 32
        static let extraSongs = 51
        static let size = 52
    }

    /// `struct MMD0song` / `struct MMD2song` — beide 788 Bytes.
    /// Die Felder ab Offset 764 liegen in beiden Varianten deckungsgleich
    /// ("Below fields are MMD0/MMD1-compatible").
    enum Song {
        static let sample = 0              // MMD0sample[63], je 8 Bytes
        static let numblocks = 504, songlen = 506
        // nur MMD0/MMD1:
        static let playseq = 508           // UBYTE[256]
        // nur MMD2/MMD3:
        static let playseqtable = 508, sectiontable = 512, trackvols = 516
        static let numtracks = 520, numpseqs = 522, trackpans = 524
        static let flags3 = 528, voladj = 532, channels = 534
        // gemeinsam:
        static let deftempo = 764, playtransp = 766, flags = 767
        static let flags2 = 768, tempo2 = 769
        static let mastervol = 786, numsamples = 787
        static let size = 788
    }

    /// `struct MMD0sample` — 8 Bytes je Instrument.
    enum Sample {
        static let rep = 0, replen = 2, midich = 4, midipreset = 5
        static let svol = 6, strans = 7
        static let size = 8
    }

    /// `struct MMD0exp` — 84 Bytes.
    enum Exp {
        static let nextmod = 0, expSmp = 4, sExtEntries = 8, sExtEntrsz = 10
        static let annotxt = 12, annolen = 16
        static let iinfo = 20, iExtEntries = 24, iExtEntrsz = 26
        static let jumpmask = 28, rgbtable = 32, channelsplit = 36
        static let nInfo = 40, songname = 44, songnamelen = 48
        static let dumps = 52, mmdinfo = 56, mmdrexx = 60, mmdcmd3x = 64
        static let size = 84
    }

    /// `struct InstrExt` — variable Größe, siehe `s_ext_entrsz`.
    /// Die Spezifikation warnt ausdrücklich: "you have to read s_ext_entrsz
    /// to get the structure sizes." Gemessen wurden 10, 18 und 24 Bytes.
    enum InstrExt {
        static let hold = 0, decay = 1, suppressMidiOff = 2, finetune = 3
        static let defaultPitch = 4, instrFlags = 5, longMidiPreset = 6  // ab V5
        static let outputDevice = 8, reserved = 9                        // ab V5.02
        static let longRepeat = 10, longReplen = 14                      // ab V7
        /// Undokumentiert, nur in 24-Byte-Varianten. Gemessen: `svol * 2`,
        /// gedeckelt bei 127 — die Instrumentlautstärke im MIDI-Bereich.
        static let midiVolume = 18
    }

    /// `struct BlockInfo` — 36 Bytes, hinter `MMD1Block.info`.
    enum BlockInfo {
        static let hlmask = 0, blockname = 4, blocknamelen = 8, pagetable = 12
        /// Undokumentiert: erster der fünf `reserved`-Einträge der
        /// Spezifikation. Zeigt auf die Befehlserweiterung (ein zweites
        /// Parameterbyte je Zelle). Gefunden über OpenMPT
        /// `Load_med.cpp`, `MMDBlockInfo.cmdExtTableOffset`.
        static let cmdExtTable = 16
        static let size = 36
    }

    /// `struct MMDDumpData` — 8 Bytes, danach `numdumps` Zeiger.
    enum DumpData { static let numdumps = 0, zeigerAb = 8 }

    /// `struct MMDDump`
    enum Dump {
        static let length = 0, data = 4, extLen = 8, name = 10
        static let nameLength = 20
    }

    /// `struct MMDMIDICmd3x`
    enum Cmd3x {
        static let structVers = 0, numOfSettings = 2
        static let ctrlrTypes = 4, ctrlrNumbers = 8
    }

    /// `struct PlaySeq` (MMD2/MMD3)
    enum PlaySeq {
        static let name = 0, nameLength = 32
        static let length = 40, seqAb = 42
    }
}
