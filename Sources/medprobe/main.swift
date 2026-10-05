import Foundation
import MEDKit

// medprobe — liest MED-Dateien und gibt aus, was drinsteht.
// Zweck: die Swift-Umsetzung gegen etwas Nachprüfbares stellen — die
// Messungen aus docs/01-quellen-und-befunde.md und das Bildschirmfoto
// aus OctaMED selbst.

struct Options {
    var files: [String] = []
    var block: Int?
    var rows: Range<Int> = 0..<16
    var tracks: Range<Int>?
    var page = 0
    var patternOnly = false
    var exportFolder: String?
    var events = false
    var layout = MIDIExport.TrackLayout.perInstrument
    var embedSysEx = false
    var eventLimit = 60
}

func range(_ s: String, standard: Range<Int>) -> Range<Int> {
    let parts = s.split(separator: "-", maxSplits: 1).map(String.init)
    guard let a = Int(parts[0]) else { return standard }
    let b = parts.count > 1 ? (Int(parts[1]) ?? a) : a
    return a..<(b + 1)
}

var o = Options()
var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--block":  i += 1; o.block = Int(args[i]); o.patternOnly = true
    case "--zeilen": i += 1; o.rows = range(args[i], standard: o.rows)
    case "--spuren": i += 1; o.tracks = range(args[i], standard: 0..<0)
    case "--seite":  i += 1; o.page = Int(args[i]) ?? 0
    case "--export": i += 1; o.exportFolder = args[i]
    case "--events": o.events = true
    case "--mit-sysex": o.embedSysEx = true
    case "--alle": o.eventLimit = Int.max
    case "--hilfe", "-h":
        print("""
        medprobe [--block N [--zeilen A-B] [--spuren A-B] [--seite N]] <datei> …

          ohne --block   Überblick: Kopfdaten, Instrumente, Dumps, Befehlsstatistik
          mit  --block   Pattern-Ansicht im OctaMED-Format

        medprobe --export <ordner> [--spuren-nach instrument|kanal|medspur]
                          [--mit-sysex] <datei> …
          schreibt je Song einen Ordner mit MIDI-Datei, entzerrter Fassung
          und sysex/ (Dumps, Manifest, Part-Belegung)

        medprobe --events [--alle] <datei> …
          spielt den Song durch und listet die MIDI-Ereignisse
        """)
        exit(0)
    default: o.files.append(args[i])
    }
    i += 1
}

guard !o.files.isEmpty else {
    FileHandle.standardError.write("medprobe: keine Datei angegeben (--hilfe)\n".data(using: .utf8)!)
    exit(2)
}

func hex2(_ v: UInt8) -> String { String(format: "%02X", v) }

for pfad in o.files {
    let url = URL(fileURLWithPath: pfad)
    let song: Song
    do {
        song = try MEDLoader.load(file: url)
    } catch {
        print("\(url.lastPathComponent): FEHLER — \(error)")
        continue
    }

    if o.events {
        let result = Player(song: song).run()
        print(EventListing.text(for: result, song: song, limit: o.eventLimit))
        print()
        print(EventListing.summary(for: result, song: song))
        print()
        continue
    }

    if let ordner = o.exportFolder {
        do {
            var optionen = MIDIExport.Options()
            optionen.layout = o.layout
            optionen.embedSysEx = o.embedSysEx
            let r = try Export.writeAll(song: song, to: URL(fileURLWithPath: ordner),
                                        options: optionen)
            let groesse = { (u: URL) in (try? Data(contentsOf: u).count) ?? 0 }
            print("\(url.lastPathComponent) -> \(r.folder.lastPathComponent)/")
            print("   \(r.midi.url.lastPathComponent)  \(r.midi.trackCount) Spuren, "
                + String(format: "%.1f s, ", r.midi.seconds) + "\(groesse(r.midi.url)) B")
            print("   \(r.relieved.url.lastPathComponent)  entzerrt, "
                + "\(groesse(r.relieved.url)) B")
            if let sysEx = r.sysEx {
                print("   sysex/  \(sysEx.dumps.count) Dumps, dumps.txt, parts.txt")
                for d in sysEx.dumps {
                    let status = d.triggeredAt != nil ? "ausgelöst" : "nur gespeichert"
                    print("      \(d.fileName)  \(d.byteCount) B  \(d.messageCount) Nachr.  "
                        + "\(d.hash)  \(status)")
                }
            }
            for w in r.midi.warnings.prefix(5) { print("   • \(w)") }
            if r.midi.warnings.count > 5 {
                print("   … \(r.midi.warnings.count - 5) weitere Hinweise")
            }
        } catch {
            print("\(url.lastPathComponent): Export fehlgeschlagen — \(error)")
        }
        continue
    }

    if let b = o.block {
        guard b >= 0, b < song.blocks.count else {
            print("Block \(b) gibt es nicht (0…\(song.blocks.count - 1))")
            continue
        }
        let block = song.blocks[b]
        let name = block.name.isEmpty ? "" : " „\(block.name)“"
        print("\(url.lastPathComponent)  —  Block \(b)\(name)"
            + "   \(block.tracks) Spuren, \(block.rows) Zeilen"
            + "   Seite \(o.page + 1)/\(block.pageCount)")
        let tracks = o.tracks ?? 0..<min(block.tracks, 10)
        print("      " + tracks.map { String(format: "%-9d", $0) }.joined(separator: " "))
        print("      " + String(repeating: "─", count: max(0, tracks.count * 10 - 1)))
        print(PatternRendering.block(block, rows: o.rows, tracks: tracks, page: o.page))
        print()
        continue
    }

    // ---- Überblick -------------------------------------------------------
    print(String(repeating: "═", count: 78))
    print("\(url.lastPathComponent)   \(song.version.name)   \(song.fileSize) Bytes")
    print("  Songname      : \(song.name.isEmpty ? "—" : song.name)")
    print("  modlen        : \(song.modlen) "
        + (Int(song.modlen) == song.fileSize ? "(= Dateigröße)" : "(WEICHT AB!)"))
    print("  Blöcke        : \(song.blocks.count)   Instrumente: \(song.instruments.count)"
        + "   weitere Songs: \(song.extraSongs)")
    let widths = Set(song.blocks.map(\.tracks)).sorted()
    let totalRows = song.blocks.reduce(0) { $0 + $1.rows }
    let pages = song.blocks.reduce(0) { $0 + $1.extraPages.count }
    print("  Spurbreiten   : \(widths)   \(totalRows) Zeilen gesamt"
        + "   Zusatzseiten: \(pages)")
    print("  Tempo         : \(song.defaultTempo)"
        + "\(song.bpmMode ? " BPM" : "")   Ticks/Zeile: \(song.ticksPerRow)"
        + "   Zeilen/Beat: \(song.rowsPerBeat)")
    print("  Transponierung: \(song.songTranspose)   Mixing: \(song.mixingMode ? "ja" : "nein")")

    if song.version.hasSections {
        print("  Sections      : \(song.sections)")
    }
    for (n, p) in song.playSequences.enumerated() {
        let nm = p.name.isEmpty ? "" : " „\(p.name)“"
        print("  Playseq \(n)\(nm): \(p.blocks.count) Einträge  \(p.blocks.prefix(16))"
            + (p.blocks.count > 16 ? " …" : ""))
    }
    let named = song.blocks.filter { !$0.name.isEmpty }
    if !named.isEmpty {
        print("  Blocknamen    : " + named.prefix(6).map { "\($0.number):\($0.name)" }
            .joined(separator: ", ") + (named.count > 6 ? " …" : ""))
    }

    let midi = song.instruments.filter(\.isMIDI)
    print("  MIDI-Instrumente: \(midi.count) von \(song.instruments.count)")
    for ins in midi {
        print(String(format: "     %2d  Kanal %2d  preset %3d  lpreset %-5@  vol %2d→%3d  tr %+d"
                     + "  hold %-4@ decay %-4@ suppOff %-6@ %@",
                     ins.number, Int(ins.midiChannel), Int(ins.midiPreset),
                     String(describing: ins.longPreset.map(String.init) ?? "—") as NSString,
                     Int(ins.defaultVolume), Int(ins.initialMIDIVolume),
                     Int(ins.transpose),
                     String(describing: ins.hold.map(String.init) ?? "—") as NSString,
                     String(describing: ins.decay.map(String.init) ?? "—") as NSString,
                     String(describing: ins.suppressNoteOff.map(String.init) ?? "—") as NSString,
                     ins.name as NSString))
    }

    print("  Dumps         : \(song.dumps.count)")
    for d in song.dumps {
        let header = d.rawData.prefix(8).map { hex2($0) }.joined()
        print("     [\(d.index)] \(d.name.isEmpty ? "(ohne Namen)" : d.name)"
            + "  \(d.rawData.count) B  \(d.messages.count) Nachrichten"
            + "  Hersteller 0x\(d.manufacturer.map { hex2($0) } ?? "??")"
            + "  \(d.isComplete ? "F0…F7 ok" : "UNVOLLSTÄNDIG")  \(header)")
    }
    if !song.cmd3xControllers.isEmpty {
        let assigned = song.cmd3xControllers.enumerated()
            .filter { $0.element.number != 0 || $0.offset == 0 }
            .map { "3\(String($0.offset + 1, radix: 16).uppercased())→CC\($0.element.number)" }
        print("  Cmd3x         : \(assigned.joined(separator: ", "))")
    }

    let stats = song.diagnostics.commandCounts.sorted { $0.key < $1.key }
    print("  Befehle       : " + stats.map { "\(hex2($0.key))×\($0.value)" }.joined(separator: ", "))

    if song.diagnostics.warnings.isEmpty {
        print("  Warnungen     : keine")
    } else {
        print("  WARNUNGEN     :")
        for w in song.diagnostics.warnings { print("     • \(w)") }
    }
    for h in song.diagnostics.notices { print("  Hinweis       : \(h)") }

    let order = NoteAnalysis.songOrder(song)
    let findings = NoteAnalysis.check(song, songOrder: order)
    var byKind: [String: [NoteFinding]] = [:]
    for b in findings {
        let key: String
        switch b.art {
        case .noteOffWithoutNote:   key = "Note-Off in Zeile 0 ohne klingende Note (Vorsorge)"
        case .noteOffMidBlock: key = "Note-Off mitten im Block, ohne klingende Note"
        case .openAtSongEnd:   key = "Am Songende noch offen"
        }
        byKind[key, default: []].append(b)
    }
    if findings.isEmpty {
        print("  Notenverlauf  : unauffällig (\(order.count) Sequenzpositionen)")
    } else {
        print("  Notenverlauf  : \(findings.count) Auffälligkeiten über \(order.count) Sequenzpositionen")
        for (art, list) in byKind.sorted(by: { $0.key < $1.key }) {
            print("     • \(art): \(list.count)×")
            for b in list.prefix(3) { print("         \(b)") }
        }
    }
}
