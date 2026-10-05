import Testing
import Foundation
@testable import MEDKit

@Test func samplesAreReadWithTheirNamesAndLengths() throws {
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    #expect(song.samples.count == 14, "\(song.samples.count) Samples")
    let alleAchtBit = song.samples.allSatisfy { $0.isPlainEightBit }
    let alleMitDaten = song.samples.allSatisfy { !$0.data.isEmpty }
    // Alle Einzelschuesse — das Material hat keine Schleifen.
    let keineSchleifen = song.samples.allSatisfy { !$0.loops }
    #expect(alleAchtBit)
    #expect(alleMitDaten)
    #expect(keineSchleifen)

    let snare = try #require(song.samples.first { $0.name == "D_Snare_074" })
    #expect(snare.data.count == 7018)
    #expect(snare.instrument == 23)
}

@Test func wavIsLosslessAgainstTheAmigaBytes() throws {
    // Ein 8-Bit-Wert mal 256 ergibt den 16-Bit-Wert. Nichts geht verloren,
    // nichts kommt hinzu — das ist der Grund fuer 16 statt 8 Bit.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    for sample in song.samples {
        let daten = SampleExport.wav(sample)

        // RIFF/WAVE-Kopf
        #expect(daten.prefix(4).elementsEqual("RIFF".utf8))
        #expect(daten[8..<12].elementsEqual("WAVE".utf8))

        // data-Abschnitt suchen und zurueckrechnen
        let bytes = Array(daten)
        var i = 12
        var gefunden = false
        while i + 8 <= bytes.count {
            let kennung = String(decoding: bytes[i..<(i + 4)], as: UTF8.self)
            let länge = Int(bytes[i+4]) | Int(bytes[i+5]) << 8
                      | Int(bytes[i+6]) << 16 | Int(bytes[i+7]) << 24
            if kennung == "data" {
                gefunden = true
                #expect(länge == sample.data.count * 2, "\(sample.name): Laenge")
                for (k, original) in sample.data.enumerated() {
                    let o = i + 8 + k * 2
                    let wert = Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o+1]) << 8)
                    if wert != Int16(original) * 256 {
                        let befund = "\(sample.name) Rahmen \(k): \(wert) statt "
                            + "\(Int16(original) * 256)"
                        #expect(Bool(false), "\(befund)")
                        break
                    }
                }
                break
            }
            i += 8 + länge + (länge % 2)
        }
        #expect(gefunden, "\(sample.name): kein data-Abschnitt")
    }
}

@Test func samplePlaybackRateComesFromOctaMEDsOwnTable() {
    // per0: DC.W 856,808,762,… — 856 ist C-3, C-5 also 214.
    // Paulas PAL-Takt geteilt durch die Periode ergibt die Rate.
    #expect(SampleExport.referenceRate == 16574)
    #expect(Int((SampleExport.palClock / 856.0).rounded()) == 4144)   // C-3
    #expect(Int((SampleExport.palClock / 428.0).rounded()) == 8287)   // C-4
}

@Test func sampleInstrumentsGetNotesInTheExport() throws {
    // Sie klingen nicht ueber MIDI, aber ihre Noten sind Musik. Mit dem
    // Sample in einem Sampler ergibt die Spur wieder das, was sie war.
    guard let url = TestFiles.file("2_ENDZEIT_NEW.OMP_WS+MU") else { return }
    let song = try MEDLoader.load(file: url)
    let result = Player(song: song).run()

    let sampleNummern = Set(song.samples.map(\.instrument))
    var mitNoten = Set<Int>()
    for event in result.events {
        guard case .noteOn = event.kind, let instrument = event.instrument else { continue }
        if sampleNummern.contains(instrument) { mitNoten.insert(instrument) }
    }
    #expect(!mitNoten.isEmpty, "kein einziges Sample-Instrument spielt")

    // Und sie landen in eigenen Spuren mit sprechendem Namen.
    let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("med2midi-s-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: ordner) }
    let r = try Export.writeAll(song: song, to: ordner)
    #expect(r.samples.count == 14)
    let reader = try SMFReader(Data(contentsOf: r.midi.url))
    let hatSampleSpur = reader.trackNames.contains { $0.hasSuffix("(Sample)") }
    #expect(hatSampleSpur, "Spurnamen: \(reader.trackNames)")
}

@Test func songsWithoutSamplesAreUnaffected() throws {
    // Die reinen MIDI-Songs duerfen sich durch all das nicht veraendern.
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        guard song.samples.isEmpty else { continue }
        let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("med2midi-o-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let r = try Export.writeAll(song: song, to: ordner)
        #expect(r.samples.isEmpty)
        let gibtOrdner = FileManager.default.fileExists(
            atPath: ordner.appendingPathComponent("samples").path)
        #expect(!gibtOrdner, "\(url.lastPathComponent) hat ein samples/ ohne Samples")
    }
}
