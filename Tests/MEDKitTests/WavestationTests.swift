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

@Test func theListingAppearsOnlyWhereItSaysSomething() throws {
    // Ohne jeden Dump wissen wir nicht, welches Geraet spielte — dann darf
    // keine Liste entstehen. Mit einem MU80-Dump koennen wir sagen, welche
    // Kanaele nicht von ihm kamen, auch ohne Korg-Dump.
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let text = WavestationListing.text(for: song)
        if song.dumps.isEmpty {
            #expect(text.isEmpty, "\(url.lastPathComponent): Liste ohne jeden Dump")
            continue
        }
        let hatKorg = song.dumps.contains { Wavestation.isWavestation($0) }
        guard !hatKorg else {
            #expect(!text.isEmpty, "\(url.lastPathComponent): Korg-Dump ohne Liste")
            continue
        }
        // Reiner MU80-Song: Liste nur, wenn ein bespielter Kanal nicht von
        // ihm bedient wird.
        let bespielt = DumpChoice.usedChannels(in: song)
        var vomMU = Set<Int>()
        if let wahl = DumpChoice.choice(in: song, for: .yamahaXG) {
            for part in MultiPart.parts(in: wahl.dump)
            where !part.isFactoryDefault {
                if let k = part.channel { vomMU.insert(k) }
            }
        }
        let erwartet = !bespielt.subtracting(vomMU).isEmpty
        #expect(text.isEmpty != erwartet, "\(url.lastPathComponent)")
    }
}

@Test func theTriggeredDumpWins() throws {
    // Vier der Dateien schicken genau einen Dump per Befehl 10 ab. Das ist
    // die Antwort auf die Frage, welcher gilt — und in allen vier Faellen ist
    // es der letzte seiner Art. Darauf beruht die Annahme fuer die uebrigen.
    var mitAusloeser = 0
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let trigger = SysExExport.triggerLocations(in: song)
        for wahl in DumpChoice.choices(in: song) {
            if case .triggered = wahl.reason {
                mitAusloeser += 1
                #expect(wahl.isCertain)
                // Der ausgeloeste ist der letzte seiner Art.
                let gleiche = song.dumps.filter { DumpChoice.device(of: $0) == wahl.device }
                #expect(gleiche.last?.index == wahl.dump.index,
                        "\(url.lastPathComponent): ausgeloest ist nicht der letzte")
                #expect(trigger[wahl.dump.index] != nil)
            }
        }
    }
    #expect(mitAusloeser >= 4, "nur \(mitAusloeser) Dateien mit Ausloeser")
}

@Test func partListingOnlyShowsChannelsTheSongPlays() throws {
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        guard DumpChoice.choice(in: song, for: .yamahaXG) != nil else { continue }
        let text = PartListing.text(for: song)
        let bespielt = DumpChoice.usedChannels(in: song)

        // Jede Kanalueberschrift muss zu einem bespielten Kanal gehoeren.
        for zeile in text.split(separator: "\n") where zeile.hasPrefix("Kanal ") {
            let teil = zeile.dropFirst(6).prefix { $0.isNumber }
            guard let kanal = Int(teil) else { continue }
            let befund = "\(url.lastPathComponent): Kanal \(kanal) steht in parts.txt, "
                + "wird aber nicht bespielt"
            #expect(bespielt.contains(kanal), "\(befund)")
        }
    }
}

@Test func factoryDefaultPartsAreRecognised() throws {
    // 24 der 32 Parts in 2_ENDZEIT_NEW sind unangetastet — das ist das
    // deutlichste Zeichen dafuer, dass der Klang von woanders kam.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let wahl = try #require(DumpChoice.choice(in: song, for: .yamahaXG))
    let parts = MultiPart.parts(in: wahl.dump)
    let werk = parts.filter(\.isFactoryDefault).count
    #expect(werk == 24, "\(werk) Parts im Werkszustand statt 24")

    // Und bei einem reinen MU80-Song darf kein bespielter Kanal im
    // Werkszustand stehen — sonst stimmte die Erkennung nicht.
    guard let andere = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let mu = try MEDLoader.load(file: andere)
    let muWahl = try #require(DumpChoice.choice(in: mu, for: .yamahaXG))
    let bespielt = DumpChoice.usedChannels(in: mu)
    let unangetastet = MultiPart.parts(in: muWahl.dump).filter {
        $0.isFactoryDefault && $0.channel.map(bespielt.contains) == true
    }
    #expect(unangetastet.isEmpty,
            "\(unangetastet.count) bespielte Kanaele im Werkszustand")
}

@Test func allConfiguredPartsOnAChannelAreNamed() throws {
    // Auf einem Kanal koennen mehrere MU80-Parts liegen. Die Spalte zeigte
    // nur den ersten und verschwieg den zweiten — dem Autor ist es am Geraet
    // aufgefallen: Kanal 4 spricht dort Ch.Aahs2 und Syn Str3 an.
    guard let url = TestFiles.file("0_DIESE_WELT.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let wahl = try #require(DumpChoice.choice(in: song, for: .yamahaXG))
    let aufVier = MultiPart.parts(in: wahl.dump).filter {
        $0.channel == 4 && !$0.isFactoryDefault
    }
    #expect(aufVier.count == 2, "\(aufVier.count) eingerichtete Parts auf Kanal 4")

    // Die Banknummern nennen die XG-Variante: Bank-LSB 16 auf Choir Aahs
    // heisst am Geraet Ch.Aahs2, LSB 35 auf SynthStrings 1 heisst Syn Str3.
    #expect(aufVier.contains { $0.voiceName == "Choir Aahs" && $0.bankLSB == 16 })
    #expect(aufVier.contains { $0.voiceName == "SynthStrings 1" && $0.bankLSB == 35 })

    let text = WavestationListing.text(for: song)
    let zeile = text.split(separator: "\n").first { $0.hasPrefix("4 ") }
    let befund = "Kanal-4-Zeile: \(zeile ?? "fehlt")"
    #expect(zeile?.contains("Choir Aahs + SynthStrings 1") == true, "\(befund)")
}
