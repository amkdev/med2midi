import Testing
import Foundation
@testable import MEDKit

@Test func multiPartDecodingIsConfirmedByTheChannels() throws {
    // Die staerkste Gegenprobe fuer die Deutung der XG-Parameter: Die
    // Empfangskanaele der belegten Parts muessen zu den Kanaelen der
    // MIDI-Instrumente der MED-Datei passen. Waere auch nur das Offset von
    // `Empfangskanal` falsch, traefe hier nichts aufeinander.
    var geprueft = 0
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        guard let dump = song.dumps.first else { continue }
        let parts = MultiPart.parts(in: dump)
        guard !parts.isEmpty else { continue }
        geprueft += 1

        #expect(parts.count == 32, "\(url.lastPathComponent): \(parts.count) Parts")

        let partKanaele = Set(parts.compactMap(\.channel))
        let medKanaele = Set(song.instruments.filter(\.sounds).map { Int($0.midiChannel) })
        let fehlend = medKanaele.subtracting(partKanaele)
        let befund = "\(url.lastPathComponent): MED spielt auf \(fehlend.sorted()), "
            + "dort empfaengt kein Part"
        #expect(fehlend.isEmpty, "\(befund)")
    }
    #expect(geprueft > 0, "keine Datei mit Dump geprueft")
}

@Test func centredParametersSitAtTheirMidpoint() throws {
    // Zweite Gegenprobe: Note Shift und Pan haben in XG den Mittelwert 0x40.
    // Stimmte das Offset nicht, laegen dort beliebige Werte.
    guard let url = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let song = try MEDLoader.load(file: url)
    let parts = MultiPart.parts(in: try #require(song.dumps.first))

    let mittig = parts.filter { $0.noteShift == 0 }.count
    #expect(mittig > parts.count / 2, "nur \(mittig) von \(parts.count) ohne Transponierung")
    #expect(parts.allSatisfy { (-64...63).contains($0.pan) })
    #expect(parts.allSatisfy { (-64...63).contains($0.noteShift) })
    #expect(parts.allSatisfy { $0.volume <= 127 })
}

@Test func layeredPartsAreFound() throws {
    // Das Wichtigste an der Auswertung: Mehrere Parts auf einem Kanal klingen
    // zusammen. Den MED-Daten sieht man das nicht an, dort ist es ein Kanal.
    guard let url = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let song = try MEDLoader.load(file: url)
    let parts = MultiPart.parts(in: try #require(song.dumps.first))

    var proKanal: [Int: Int] = [:]
    for part in parts { if let k = part.channel { proKanal[k, default: 0] += 1 } }
    #expect(proKanal[5] == 3, "Kanal 5 sollte drei Parts tragen")
    #expect(proKanal.values.contains { $0 > 1 })
}

@Test func partListingNamesEveryPlayedChannel() throws {
    guard let url = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let song = try MEDLoader.load(file: url)
    let text = PartListing.text(for: song)
    for instrument in song.instruments where instrument.sounds {
        #expect(text.contains("Kanal \(instrument.midiChannel)"))
    }
    #expect(text.contains("Parts übereinander"))
}
