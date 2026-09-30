import Foundation

/// Eine Zelle: Note, Instrument und der Befehl der ersten Befehlsseite.
/// Weitere Seiten stehen in `Block.zusatzSeiten`.
public struct Zelle: Equatable, Sendable {
    public let note: UInt8          // 0 = ---, 1 = C-1
    public let instrument: UInt8    // 0 = keines
    public let befehl: Befehl

    public init(note: UInt8, instrument: UInt8, befehl: Befehl) {
        self.note = note
        self.instrument = instrument
        self.befehl = befehl
    }

    public static let leer = Zelle(note: 0, instrument: 0,
                                   befehl: Befehl(nummer: 0, daten: 0))

    /// Notenname wie in OctaMED: 1 = C-1, 2 = C#1 …
    public var notenName: String {
        guard note > 0 else { return "---" }
        let namen = ["C-", "C#", "D-", "D#", "E-", "F-",
                     "F#", "G-", "G#", "A-", "A#", "B-"]
        let n = Int(note) - 1
        return "\(namen[n % 12])\(n / 12 + 1)"
    }
}

public struct Block: Sendable {
    public let nummer: Int
    public let name: String
    public let spuren: Int
    public let zeilen: Int
    /// Zeile-vor-Spur, wie in der Datei: `zellen[zeile * spuren + spur]`.
    public let zellen: [Zelle]
    /// Zusätzliche Befehlsseiten (`BlockCmdPageTable`), je 2 Bytes pro Zelle,
    /// gleiche Anordnung. Leer, wenn der Block nur eine Seite hat.
    public let zusatzSeiten: [[Befehl]]

    public init(nummer: Int, name: String, spuren: Int, zeilen: Int,
                zellen: [Zelle], zusatzSeiten: [[Befehl]]) {
        self.nummer = nummer; self.name = name
        self.spuren = spuren; self.zeilen = zeilen
        self.zellen = zellen; self.zusatzSeiten = zusatzSeiten
    }

    public func zelle(zeile: Int, spur: Int) -> Zelle {
        guard zeile >= 0, zeile < zeilen, spur >= 0, spur < spuren else { return .leer }
        return zellen[zeile * spuren + spur]
    }

    /// Befehl einer bestimmten Seite. Seite 0 ist die Hauptseite.
    public func befehl(zeile: Int, spur: Int, seite: Int) -> Befehl {
        if seite == 0 { return zelle(zeile: zeile, spur: spur).befehl }
        let i = seite - 1
        guard i < zusatzSeiten.count else { return Befehl(nummer: 0, daten: 0) }
        let index = zeile * spuren + spur
        guard index < zusatzSeiten[i].count else { return Befehl(nummer: 0, daten: 0) }
        return zusatzSeiten[i][index]
    }

    public var seitenAnzahl: Int { 1 + zusatzSeiten.count }
}

public struct Instrument: Sendable {
    public let nummer: Int          // 1-basiert wie in der Anzeige
    public let name: String
    public let midiKanal: UInt8     // 0 = kein MIDI
    public let midiPreset: UInt8
    public let langesPreset: UInt16?
    public let standardLautstärke: UInt8   // svol, 0–64
    public let transponierung: Int8
    public let hold: UInt8?
    public let decay: UInt8?
    public let noteOffUnterdrücken: Bool?
    /// Undokumentiertes Feld der 24-Byte-InstrExt: Lautstärke im MIDI-Bereich.
    public let midiLautstärke: UInt8?

    public var istMIDI: Bool { midiKanal > 0 }
    public var klingt: Bool { istMIDI && standardLautstärke > 0 }

    /// Anfangslautstärke für den Export. Wo das undokumentierte Feld vorliegt,
    /// ist es der genauere Wert — es ist bereits die Zahl, die das schreibende
    /// Programm gesendet hätte.
    public var midiAnfangsLautstärke: UInt8 {
        midiLautstärke ?? Befehlskatalog.midiLautstärke(ausSvol: standardLautstärke)
    }
}

public struct SysExDump: Sendable {
    public let index: Int
    public let name: String
    public let rohdaten: [UInt8]

    /// Ein "Dump" ist in der Praxis eine Folge einzelner SysEx-Nachrichten.
    /// Gemessen: 408 Nachrichten in 13 154 Bytes.
    public var nachrichten: [ArraySlice<UInt8>] {
        var ergebnis: [ArraySlice<UInt8>] = []
        var i = rohdaten.startIndex
        while i < rohdaten.endIndex, rohdaten[i] == 0xF0 {
            guard let ende = rohdaten[i...].firstIndex(of: 0xF7) else { break }
            ergebnis.append(rohdaten[i...ende])
            i = rohdaten.index(after: ende)
        }
        return ergebnis
    }

    public var istVollständig: Bool {
        rohdaten.first == 0xF0 && rohdaten.last == 0xF7
    }

    /// Herstellerkennung der ersten Nachricht. 0x43 = Yamaha.
    public var hersteller: UInt8? {
        rohdaten.count > 1 ? rohdaten[1] : nil
    }
}

public struct Playsequenz: Sendable {
    public let name: String
    public let blöcke: [Int]
}

public struct Song: Sendable {
    public let version: MMDVersion
    public let name: String
    public let dateiname: String
    public let modlen: UInt32
    public let dateigröße: Int
    public let weitereSongs: Int

    public let standardTempo: UInt16
    public let ticksProZeile: UInt8
    public let bpmModus: Bool
    public let zeilenProBeat: Int
    public let songTransponierung: Int8
    public let mixingModus: Bool

    public let instrumente: [Instrument]
    public let blöcke: [Block]
    public let playsequenzen: [Playsequenz]
    public let sections: [Int]
    public let dumps: [SysExDump]
    /// Controller-Nummern für die Befehle 31–3F, aus `MMDMIDICmd3x`.
    public let cmd3xController: [(typ: UInt8, nummer: UInt16)]

    public let diagnose: Diagnose
}
