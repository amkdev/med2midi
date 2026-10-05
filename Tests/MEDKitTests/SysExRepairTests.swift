import Testing
import Foundation
@testable import MEDKit

@Test func repairFixesTheDamagedDumpCompletely() throws {
    // Am Geraet gemessen: Der MU80 meldete beim Empfang dieses Dumps
    // "Check Sum Error!". Fuenf Bytes sind beschaedigt, jedes auf Bitebene.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let dump = try #require(song.dumps.first { $0.manufacturer == 0x43 })

    #expect(!dump.check().isIntact, "Der bekannte Schaden ist weg")

    let r = SysExRepair.repair(dump)
    #expect(r.changes.count == 5, "\(r.changes.count) Aenderungen statt 5")
    #expect(r.unresolved.isEmpty, "\(r.unresolved)")

    // Danach muss der Dump vollstaendig in Ordnung sein — 408 Nachrichten,
    // wie bei allen intakten Dumps des Autors.
    let repariert = SysExDump(index: dump.index, name: dump.name, rawData: r.data)
    let check = repariert.check()
    #expect(check.messages == 408, "\(check.messages) Nachrichten")
    #expect(check.isIntact, "\(check.text)")
    #expect(repariert.isComplete)

    // Und die Aenderungen sind alle Bitreparaturen, keine Umschreibungen.
    for c in r.changes {
        let gekippt = (c.from ^ c.to).nonzeroBitCount
        #expect(gekippt <= 2, "\(gekippt) Bits an Offset \(c.offset)")
    }
}

@Test func repairLeavesHealthyDumpsAlone() throws {
    // Entscheidend: An heilen Daten darf nichts veraendert werden.
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        for dump in song.dumps where dump.check().isIntact {
            let r = SysExRepair.repair(dump)
            #expect(r.changes.isEmpty,
                    "\(url.lastPathComponent) Dump \(dump.index): \(r.changes.count) Aenderungen")
            #expect(r.data == dump.rawData)
        }
    }
}

@Test func repairKeepsAwayFromOtherManufacturers() throws {
    // Der Korg-Dump folgt einem anderen Schema. Daran wird nicht gerechnet.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let korg = try #require(song.dumps.first { $0.manufacturer == 0x42 })
    let r = SysExRepair.repair(korg)
    #expect(r.changes.isEmpty)
    #expect(r.data == korg.rawData)
}

@Test func repairRefusesWhenTheEvidenceIsAmbiguous() throws {
    // Ein beschaedigtes Byte, zu dem es keine Geschwister gibt, darf nicht
    // geraten werden. Nachgestellt an einem intakten Dump: ein Datenbyte in
    // der ersten Nachricht verbiegen und pruefen, dass nichts passiert, was
    // die Pruefsumme nicht beweist.
    guard let url = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let song = try MEDLoader.load(file: url)
    let dump = try #require(song.dumps.first)
    // In den Datenbereich der ersten Nachricht greifen, nicht in den Kopf:
    // Byteanzahl, Adresse und Daten gehen in die Pruefsumme ein, Statusbyte
    // und Geraetenummer nicht. Ein Treffer dort bliebe folgenlos.
    let erste = Array(dump.messages[0])
    let datenAb = 9
    #expect(erste.count > datenAb + 2, "erste Nachricht zu kurz fuer den Test")
    var bytes = dump.rawData
    bytes[datenAb] = bytes[datenAb] ^ 0x01
    let beschaedigt = SysExDump(index: 0, name: "Probe", rawData: bytes)
    let r = SysExRepair.repair(beschaedigt)
    // Entweder wird es beweisbar repariert oder gemeldet — aber nie still
    // mit einem geratenen Wert ueberschrieben.
    if r.changes.isEmpty {
        #expect(!r.unresolved.isEmpty, "Schaden weder repariert noch gemeldet")
    } else {
        let repariert = SysExDump(index: 0, name: "Probe", rawData: r.data)
        #expect(repariert.check().isIntact, "Reparatur hat es nicht in Ordnung gebracht")
    }
}
