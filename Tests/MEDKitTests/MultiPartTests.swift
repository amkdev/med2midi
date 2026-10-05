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

@Test func meterEstimateNarrowsWhereItCan() throws {
    // Ein Tracker speichert keine Taktart. Die Schaetzung grenzt ein, und wo
    // sie das nicht kann, sagt sie es — statt eine Zahl zu erfinden.
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let takt = MeterEstimate.estimate(song: song)

        #expect(!takt.blockRows.isEmpty, "\(url.lastPathComponent): keine Bloecke")
        #expect(takt.rowsPerBeat > 0)
        // Jeder Kandidat muss wirklich zu allen Bloecken passen.
        for kandidat in takt.candidates {
            for rows in takt.blockRows {
                let befund = "\(url.lastPathComponent): \(kandidat)/4 passt nicht zu \(rows) Zeilen"
                #expect(rows % (kandidat * takt.rowsPerBeat) == 0, "\(befund)")
            }
        }
        // Ohne ganze Viertel darf es keine Kandidaten geben.
        if !takt.wholeBeats { #expect(takt.candidates.isEmpty) }
        #expect(!takt.text.isEmpty)
    }
}

@Test func sendBlocksDoNotDistortTheMeterEstimate() throws {
    // Die Laenge eines Sendeblocks ist die Ladezeit des MU80. Zaehlte sie mit,
    // waere die Schaetzung wertlos: In N_ich_will_neues hat er 78 Zeilen und
    // teilt sich durch nichts.
    guard let url = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let song = try MEDLoader.load(file: url)
    let takt = MeterEstimate.estimate(song: song)
    #expect(!takt.blockRows.contains(78))
    #expect(takt.blockRows == [48, 96, 192])
    #expect(takt.candidates == [2, 3, 6])
}

@Test func medFilesAreRecognisedByTheirMagicNotTheirExtension() throws {
    // Auf dem Amiga hatten die Dateien keine Endung. Der Autor hat sie spaeter
    // von Hand benannt — .med, .MMD, .mmd1, und gepackte tragen zusaetzlich
    // .pp. Die Kennung am Dateianfang ist das einzig Verlaessliche.
    var endungen = Set<String>()
    for url in TestFiles.all {
        endungen.insert(url.pathExtension.lowercased())
        let kopf = try FileHandle(forReadingFrom: url).read(upToCount: 4)
        let bytes = Array(try #require(kopf))
        #expect(bytes[0...2].elementsEqual("MMD".utf8), "\(url.lastPathComponent)")
        #expect((0x30...0x33).contains(bytes[3]), "\(url.lastPathComponent)")
    }
    // Das Material hat tatsaechlich mehrere Endungen — sonst waere der Test
    // ohne Aussage.
    #expect(endungen.count > 1, "nur eine Endung im Material: \(endungen)")
}

@Test func folderScanFindsFilesWithoutExtensionAndSkipsOthers() throws {
    // Nachgestellt, was beim Ablegen eines Archivordners passiert: verschachtelte
    // Ordner, eine MED-Datei ohne jede Endung, und Dateien, die keine sind.
    guard let quelle = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let wurzel = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("med2midi-scan-\(UUID().uuidString)")
    let unter = wurzel.appendingPathComponent("tiefer/noch tiefer")
    defer { try? FileManager.default.removeItem(at: wurzel) }
    try FileManager.default.createDirectory(at: unter, withIntermediateDirectories: true)

    try Data(contentsOf: quelle).write(to: unter.appendingPathComponent("ohne_endung"))
    try Data("kein MED".utf8).write(to: wurzel.appendingPathComponent("liesmich.txt"))
    try Data([0x4D, 0x4D]).write(to: wurzel.appendingPathComponent("zu_kurz"))

    let gefunden = MEDFileScan.medFiles(at: wurzel)
    #expect(gefunden.count == 1, "\(gefunden.map(\.lastPathComponent))")
    #expect(gefunden.first?.lastPathComponent == "ohne_endung")

    // Eine einzelne Datei direkt, nicht nur Ordner.
    #expect(MEDFileScan.medFiles(at: quelle).count == 1)
    #expect(MEDFileScan.medFiles(at: wurzel.appendingPathComponent("liesmich.txt")).isEmpty)
}
