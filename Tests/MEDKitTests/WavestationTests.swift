import Testing
import Foundation
@testable import MEDKit

@Test func wavestationDumpIsRecognised() throws {
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let ws = try #require(song.dumps.first { Wavestation.isWavestation($0) })
    #expect(ws.manufacturer == 0x42)
    #expect(ws.rawData[3] == 0x28)          // Modell Wavestation

    // Die anderen Dumps duerfen nicht faelschlich dazuzaehlen.
    for dump in song.dumps where dump.manufacturer == 0x43 {
        #expect(!Wavestation.isWavestation(dump))
    }
}

@Test func thePayloadIsNibblePackedNotSevenBit() throws {
    // Korg packt in vielen Geraeten acht MIDI-Bytes zu sieben Datenbytes.
    // Hier nicht: Von allen Nutzbytes liegt genau eines ueber 15, und das ist
    // das Pruefbyte am Ende. Es sind Nibbles.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let ws = try #require(song.dumps.first { Wavestation.isWavestation($0) })

    let nutz = ws.rawData[5..<(ws.rawData.count - 1)]
    let ueber15 = nutz.filter { $0 > 15 }.count
    #expect(ueber15 == 1, "\(ueber15) Bytes ueber 15 — dann waere es keine Nibble-Packung")

    let ent = Wavestation.unpack(ws)
    #expect(ent.count == nutz.count / 2)
}

@Test func twoFullBanksOfPerformancesAndPatches() throws {
    // Die Wavestation fuehrt 50 Performances und 35 Patches je Bank. Zwei
    // RAM-Baenke ergeben 100 und 70 — das ist die Gegenprobe dafuer, dass die
    // Blockgrenzen stimmen und kein Platz doppelt oder gar nicht zaehlt.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let ws = try #require(song.dumps.first { Wavestation.isWavestation($0) })
    let inhalt = Wavestation.read(ws)

    #expect(inhalt.performances.count == 100, "\(inhalt.performances.count) Performances")
    #expect(inhalt.patches.count == 70, "\(inhalt.patches.count) Patches")
    #expect(inhalt.performances.first?.name == "Dark Village")
    #expect(inhalt.patches.first?.name == "Destructo")

    // Fortlaufend nummeriert, ohne Luecke.
    for (i, e) in inhalt.performances.enumerated() { #expect(e.index == i) }
    for (i, e) in inhalt.patches.enumerated() { #expect(e.index == i) }
}

@Test func theAuthorsInstrumentNamesAreFoundInTheDump() throws {
    // Der eigentliche Zweck: Der Autor hat seine MED-Instrumente nach den
    // gewaehlten Klaengen benannt. Findet sich der Name im Dump wieder, ist
    // die Entschluesselung bestaetigt — und er weiss, welchen Klang er suchte.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let ws = try #require(song.dumps.first { Wavestation.isWavestation($0) })
    let namen = Set(Wavestation.read(ws).performances.map {
        $0.name.lowercased().filter { $0.isLetter || $0.isNumber }
    })

    var getroffen = 0
    var gesamt = 0
    for instrument in song.instruments where instrument.isMIDI && !instrument.name.isEmpty {
        gesamt += 1
        if namen.contains(instrument.name.lowercased().filter({ $0.isLetter || $0.isNumber })) {
            getroffen += 1
        }
    }
    let befund = "\(getroffen) von \(gesamt) MED-Instrumentnamen im Dump gefunden"
    #expect(getroffen >= 7, "\(befund)")
}

@Test func songsWithoutAWavestationDumpGetNoListing() throws {
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        guard !song.dumps.contains(where: { Wavestation.isWavestation($0) }) else { continue }
        #expect(WavestationListing.text(for: song).isEmpty, "\(url.lastPathComponent)")
    }
}
