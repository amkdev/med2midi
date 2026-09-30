import Foundation
import MEDKit

// medprobe — liest MED-Dateien und gibt aus, was drinsteht.
// Zweck: die Swift-Umsetzung gegen etwas Nachprüfbares stellen — die
// Messungen aus docs/01-quellen-und-befunde.md und das Bildschirmfoto
// aus OctaMED selbst.

struct Optionen {
    var dateien: [String] = []
    var block: Int?
    var zeilen: Range<Int> = 0..<16
    var spuren: Range<Int>?
    var seite = 0
    var nurPattern = false
}

func bereich(_ s: String, standard: Range<Int>) -> Range<Int> {
    let teile = s.split(separator: "-", maxSplits: 1).map(String.init)
    guard let a = Int(teile[0]) else { return standard }
    let b = teile.count > 1 ? (Int(teile[1]) ?? a) : a
    return a..<(b + 1)
}

var o = Optionen()
var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--block":  i += 1; o.block = Int(args[i]); o.nurPattern = true
    case "--zeilen": i += 1; o.zeilen = bereich(args[i], standard: o.zeilen)
    case "--spuren": i += 1; o.spuren = bereich(args[i], standard: 0..<0)
    case "--seite":  i += 1; o.seite = Int(args[i]) ?? 0
    case "--hilfe", "-h":
        print("""
        medprobe [--block N [--zeilen A-B] [--spuren A-B] [--seite N]] <datei> …

          ohne --block   Überblick: Kopfdaten, Instrumente, Dumps, Befehlsstatistik
          mit  --block   Pattern-Ansicht im OctaMED-Format
        """)
        exit(0)
    default: o.dateien.append(args[i])
    }
    i += 1
}

guard !o.dateien.isEmpty else {
    FileHandle.standardError.write("medprobe: keine Datei angegeben (--hilfe)\n".data(using: .utf8)!)
    exit(2)
}

func hex2(_ v: UInt8) -> String { String(format: "%02X", v) }

for pfad in o.dateien {
    let url = URL(fileURLWithPath: pfad)
    let song: Song
    do {
        song = try MEDLoader.lade(datei: url)
    } catch {
        print("\(url.lastPathComponent): FEHLER — \(error)")
        continue
    }

    if let b = o.block {
        guard b >= 0, b < song.blöcke.count else {
            print("Block \(b) gibt es nicht (0…\(song.blöcke.count - 1))")
            continue
        }
        let block = song.blöcke[b]
        let name = block.name.isEmpty ? "" : " „\(block.name)“"
        print("\(url.lastPathComponent)  —  Block \(b)\(name)"
            + "   \(block.spuren) Spuren, \(block.zeilen) Zeilen"
            + "   Seite \(o.seite + 1)/\(block.seitenAnzahl)")
        let spuren = o.spuren ?? 0..<min(block.spuren, 10)
        print("      " + spuren.map { String(format: "%-9d", $0) }.joined(separator: " "))
        print("      " + String(repeating: "─", count: max(0, spuren.count * 10 - 1)))
        print(PatternDarstellung.block(block, zeilen: o.zeilen, spuren: spuren, seite: o.seite))
        print()
        continue
    }

    // ---- Überblick -------------------------------------------------------
    print(String(repeating: "═", count: 78))
    print("\(url.lastPathComponent)   \(song.version.name)   \(song.dateigröße) Bytes")
    print("  Songname      : \(song.name.isEmpty ? "—" : song.name)")
    print("  modlen        : \(song.modlen) "
        + (Int(song.modlen) == song.dateigröße ? "(= Dateigröße)" : "(WEICHT AB!)"))
    print("  Blöcke        : \(song.blöcke.count)   Instrumente: \(song.instrumente.count)"
        + "   weitere Songs: \(song.weitereSongs)")
    let breiten = Set(song.blöcke.map(\.spuren)).sorted()
    let zeilenGesamt = song.blöcke.reduce(0) { $0 + $1.zeilen }
    let seiten = song.blöcke.reduce(0) { $0 + $1.zusatzSeiten.count }
    print("  Spurbreiten   : \(breiten)   \(zeilenGesamt) Zeilen gesamt"
        + "   Zusatzseiten: \(seiten)")
    print("  Tempo         : \(song.standardTempo)"
        + "\(song.bpmModus ? " BPM" : "")   Ticks/Zeile: \(song.ticksProZeile)"
        + "   Zeilen/Beat: \(song.zeilenProBeat)")
    print("  Transponierung: \(song.songTransponierung)   Mixing: \(song.mixingModus ? "ja" : "nein")")

    if song.version.hatSections {
        print("  Sections      : \(song.sections)")
    }
    for (n, p) in song.playsequenzen.enumerated() {
        let nm = p.name.isEmpty ? "" : " „\(p.name)“"
        print("  Playseq \(n)\(nm): \(p.blöcke.count) Einträge  \(p.blöcke.prefix(16))"
            + (p.blöcke.count > 16 ? " …" : ""))
    }
    let benannte = song.blöcke.filter { !$0.name.isEmpty }
    if !benannte.isEmpty {
        print("  Blocknamen    : " + benannte.prefix(6).map { "\($0.nummer):\($0.name)" }
            .joined(separator: ", ") + (benannte.count > 6 ? " …" : ""))
    }

    let midi = song.instrumente.filter(\.istMIDI)
    print("  MIDI-Instrumente: \(midi.count) von \(song.instrumente.count)")
    for ins in midi {
        print(String(format: "     %2d  Kanal %2d  preset %3d  lpreset %-5@  vol %2d→%3d  tr %+d"
                     + "  hold %-4@ decay %-4@ suppOff %-6@ %@",
                     ins.nummer, Int(ins.midiKanal), Int(ins.midiPreset),
                     String(describing: ins.langesPreset.map(String.init) ?? "—") as NSString,
                     Int(ins.standardLautstärke), Int(ins.midiAnfangsLautstärke),
                     Int(ins.transponierung),
                     String(describing: ins.hold.map(String.init) ?? "—") as NSString,
                     String(describing: ins.decay.map(String.init) ?? "—") as NSString,
                     String(describing: ins.noteOffUnterdrücken.map(String.init) ?? "—") as NSString,
                     ins.name as NSString))
    }

    print("  Dumps         : \(song.dumps.count)")
    for d in song.dumps {
        let kopf = d.rohdaten.prefix(8).map { hex2($0) }.joined()
        print("     [\(d.index)] \(d.name.isEmpty ? "(ohne Namen)" : d.name)"
            + "  \(d.rohdaten.count) B  \(d.nachrichten.count) Nachrichten"
            + "  Hersteller 0x\(d.hersteller.map { hex2($0) } ?? "??")"
            + "  \(d.istVollständig ? "F0…F7 ok" : "UNVOLLSTÄNDIG")  \(kopf)")
    }
    if !song.cmd3xController.isEmpty {
        let belegt = song.cmd3xController.enumerated()
            .filter { $0.element.nummer != 0 || $0.offset == 0 }
            .map { "3\(String($0.offset + 1, radix: 16).uppercased())→CC\($0.element.nummer)" }
        print("  Cmd3x         : \(belegt.joined(separator: ", "))")
    }

    let stat = song.diagnose.befehlsStatistik.sorted { $0.key < $1.key }
    print("  Befehle       : " + stat.map { "\(hex2($0.key))×\($0.value)" }.joined(separator: ", "))

    if song.diagnose.warnungen.isEmpty {
        print("  Warnungen     : keine")
    } else {
        print("  WARNUNGEN     :")
        for w in song.diagnose.warnungen { print("     • \(w)") }
    }
    for h in song.diagnose.hinweise { print("  Hinweis       : \(h)") }
}
