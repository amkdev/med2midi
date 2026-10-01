import Testing
import Foundation
@testable import MEDKit

/// Die Songdateien sind privat und nicht versioniert. Tests, die sie brauchen,
/// überspringen sich sauber, wenn `songs/` fehlt.
enum Testmaterial {
    static var ordner: URL? {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { u.deleteLastPathComponent() }
        let songs = u.appendingPathComponent("songs")
        return FileManager.default.fileExists(atPath: songs.path) ? songs : nil
    }

    static func datei(_ name: String) -> URL? {
        guard let o = ordner else { return nil }
        let u = o.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static var alle: [URL] {
        guard let o = ordner else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: o,
            includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

// MARK: - Grundlagen ohne Testmaterial

@Test func versionAusKennung() {
    #expect(MMDVersion(kennung: 0x4D4D4430) == .mmd0)
    #expect(MMDVersion(kennung: 0x4D4D4433) == .mmd3)
    #expect(MMDVersion(kennung: 0x4D4D4434) == nil)   // MMD4 ist reserviert
    #expect(MMDVersion(kennung: 0x4D4F4430) == nil)   // "MOD0"
}

@Test func blockLayoutJeVersion() {
    #expect(MMDVersion.mmd0.notenBytes == 3)
    #expect(MMDVersion.mmd0.blockKopfBytes == 2)
    #expect(MMDVersion.mmd1.notenBytes == 4)
    #expect(MMDVersion.mmd1.blockKopfBytes == 8)
    #expect(MMDVersion.mmd3.hatSections)
    #expect(!MMDVersion.mmd1.hatSections)
}

@Test func notennamenWieInOctaMED() {
    // Spezifikation: "0 = ---, 1 = C-1, 2 = C#1..."
    #expect(Zelle(note: 0, instrument: 0, befehl: .init(nummer: 0, daten: 0)).notenName == "---")
    #expect(Zelle(note: 1, instrument: 0, befehl: .init(nummer: 0, daten: 0)).notenName == "C-1")
    #expect(Zelle(note: 2, instrument: 0, befehl: .init(nummer: 0, daten: 0)).notenName == "C#1")
    #expect(Zelle(note: 13, instrument: 0, befehl: .init(nummer: 0, daten: 0)).notenName == "C-2")
}

@Test func befehlNullMitDatenIstNichtLeer() {
    // Befehl 00 mit Datenbyte != 0 ist der MIDI-Controller-Wert.
    #expect(Befehl(nummer: 0, daten: 0).istLeer)
    #expect(!Befehl(nummer: 0, daten: 0x3A).istLeer)
}

@Test func befehlskatalogMIDISeite() {
    // Die fünf Stellen, an denen Tutka falsch liegt.
    #expect(Befehlskatalog.midiWirkung(0x05) == .controllerNummer)
    #expect(Befehlskatalog.midiWirkung(0x0A) == .polyphonerAftertouch)
    #expect(Befehlskatalog.midiWirkung(0x16) == .blockWiederholen)
    #expect(Befehlskatalog.midiWirkung(0x17) == .lautstärkeController)
    #expect(Befehlskatalog.midiWirkung(0x1C) == .midiPreset)
}

@Test func tempoSonderfälle() {
    #expect(TempoSonderfall(daten: 0xFF) == .noteStoppen)
    #expect(TempoSonderfall(daten: 0xFE) == .songAnhalten)
    #expect(TempoSonderfall(daten: 0xF7) == .wartenBisGesendet)
    #expect(TempoSonderfall(daten: 0xFA) == .holdPedalAn)
    #expect(TempoSonderfall(daten: 0x40) == .tempoSetzen(0x40))
}

@Test func velocityNachMessungAmOriginal() {
    // Am Amiga gemessen: 40 -> 79, 64 -> 127, 65..127 -> 127.
    #expect(Befehlskatalog.velocity(ausBefehlsdaten: 40) == 79)
    #expect(Befehlskatalog.velocity(ausBefehlsdaten: 64) == 127)
    #expect(Befehlskatalog.velocity(ausBefehlsdaten: 65) == 127)
    #expect(Befehlskatalog.velocity(ausBefehlsdaten: 127) == 127)
    #expect(Befehlskatalog.velocity(ausBefehlsdaten: 0) == 0)
    // Die beiden verworfenen Formeln ergaeben hier andere Werte.
    #expect(Befehlskatalog.velocity(ausBefehlsdaten: 40) != 80)   // nicht x2
    #expect(Befehlskatalog.velocity(ausBefehlsdaten: 40) != 53)   // nicht Tutka
}

@Test func svolNachMIDI() {
    // Belegt am undokumentierten InstrExt-Feld der 24-Byte-Variante.
    #expect(Befehlskatalog.midiLautstärke(ausSvol: 47) == 94)
    #expect(Befehlskatalog.midiLautstärke(ausSvol: 64) == 127)
    #expect(Befehlskatalog.midiLautstärke(ausSvol: 32) == 64)
}

@Test func kurzeDateiWirdAbgewiesen() {
    #expect(throws: MEDError.self) { try MEDLoader.lade(bytes: [0x4D, 0x4D, 0x44, 0x31]) }
}

@Test func falscheKennungWirdAbgewiesen() {
    let bytes = [UInt8](repeating: 0, count: 100)
    #expect(throws: MEDError.self) { try MEDLoader.lade(bytes: bytes) }
}

// MARK: - Gegen die echten Dateien

@Test func alleTestdateienLadenUndModlenStimmt() throws {
    let dateien = Testmaterial.alle
    guard !dateien.isEmpty else { return }   // songs/ fehlt — nichts zu prüfen
    for url in dateien {
        let song = try MEDLoader.lade(datei: url)
        // modlen ist die eingebaute Selbstprüfung des Formats.
        #expect(Int(song.modlen) == song.dateigröße,
                "\(url.lastPathComponent): modlen \(song.modlen) != \(song.dateigröße)")
        #expect(!song.blöcke.isEmpty)
    }
}

@Test func keineUnbekanntenBefehleImTestmaterial() throws {
    for url in Testmaterial.alle {
        let song = try MEDLoader.lade(datei: url)
        let unbekannt = song.diagnose.befehlsStatistik.keys.filter {
            Befehlskatalog.midiWirkung($0) == .unbekannt
        }.sorted()
        let liste = unbekannt.map { String(format: "%02X", $0) }.joined(separator: ", ")
        #expect(unbekannt.isEmpty, "\(url.lastPathComponent): unbekannte Befehle \(liste)")
    }
}

@Test func keineKanalkollisionKlingenderInstrumente() throws {
    for url in Testmaterial.alle {
        let song = try MEDLoader.lade(datei: url)
        let kollisionen = song.diagnose.warnungen.filter {
            if case .kanalKollision = $0.art { return true }
            return false
        }
        #expect(kollisionen.isEmpty, "\(url.lastPathComponent): \(kollisionen)")
    }
}

/// Die wichtigste Probe: gegen ein Bildschirmfoto aus OctaMED SoundStudio
/// V1.03c auf dem Amiga. Vorlage in docs/01-quellen-und-befunde.md.
@Test func patternAnsichtStimmtMitOctaMEDÜberein() throws {
    guard let url = Testmaterial.datei("O_Wie_Eine_Marionette.MMD") else { return }
    let song = try MEDLoader.lade(datei: url)
    let block = song.blöcke[4]

    #expect(block.spuren == 20)
    #expect(block.zeilen == 512)

    let erwartet = """
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
    let tatsächlich = PatternDarstellung.block(block, zeilen: 0..<9, spuren: 0..<10)
    #expect(tatsächlich == erwartet)
}

/// Der spurbezogene Kanalzustand, an dem Block belegt.
@Test func befehl17LöstProSpurAufVerschiedeneKanäleAuf() throws {
    guard let url = Testmaterial.datei("O_Wie_Eine_Marionette.MMD") else { return }
    let song = try MEDLoader.lade(datei: url)
    let block = song.blöcke[4]

    var letztesInstrument: [Int: UInt8] = [:]
    var treffer: [(spur: Int, kanal: UInt8, wert: UInt8)] = []
    for zeile in 0...1 {
        for spur in 0..<block.spuren {
            let z = block.zelle(zeile: zeile, spur: spur)
            if z.instrument != 0 { letztesInstrument[spur] = z.instrument }
            if zeile == 1, z.befehl.nummer == 0x17, let ins = letztesInstrument[spur] {
                let kanal = song.instrumente[Int(ins) - 1].midiKanal
                treffer.append((spur, kanal, z.befehl.daten))
            }
        }
    }
    #expect(treffer.count == 4)
    #expect(Set(treffer.map(\.kanal)) == [10, 1, 2, 3])
    #expect(Set(treffer.map(\.wert)) == [0x58, 0x7F, 0x70])
}

@Test func dumpZerfälltInEinzelneSysExNachrichten() throws {
    guard let url = Testmaterial.datei("N_WOISTDAS_MU80.med") else { return }
    let song = try MEDLoader.lade(datei: url)
    let dump = try #require(song.dumps.first)
    #expect(dump.rohdaten.count == 13154)
    #expect(dump.istVollständig)
    #expect(dump.hersteller == 0x43)              // Yamaha
    #expect(dump.nachrichten.count == 408)
    // Die letzte Nachricht trägt die MU80-eigene Model-ID 0x49, nicht XG 0x4C.
    let letzte = try #require(dump.nachrichten.last)
    #expect(letzte[letzte.startIndex + 3] == 0x49)
}

@Test func instrExtGrößeWirdRespektiert() throws {
    // sehnsuchts_blues hat 10 Bytes je Eintrag. Das deckt long_midi_preset
    // (Offset 6, 2 Bytes) noch ab, das undokumentierte Feld bei Offset 18
    // dagegen nicht.
    if let url = Testmaterial.datei("sehnsuchts_blues.MMD1.pp") {
        let song = try MEDLoader.lade(datei: url)
        #expect(song.instrumente.allSatisfy { $0.langesPreset != nil })
        #expect(song.instrumente.allSatisfy { $0.midiLautstärke == nil })
        // Ohne das Feld wird aus svol gerechnet.
        if let bass = song.instrumente.first(where: { $0.name == "Bass" }) {
            #expect(bass.standardLautstärke == 50)
            #expect(bass.midiAnfangsLautstärke == 100)
        }
    }
    // N_WOISTDAS hat 24 Bytes — das undokumentierte MIDI-Lautstärkefeld ist da.
    if let url = Testmaterial.datei("N_WOISTDAS_MU80.med") {
        let song = try MEDLoader.lade(datei: url)
        let erstes = try #require(song.instrumente.first)
        #expect(erstes.midiLautstärke == 94)      // svol 47
        #expect(erstes.standardLautstärke == 47)
    }
}
