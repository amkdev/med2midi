import Testing
import Foundation
@testable import MEDKit

/// Minimal reader, only as far as the tests need: it has to notice when the
/// writer produces something a DAW would choke on.
struct SMFReader {
    enum Event { case noteOn(channel: Int, note: Int, velocity: Int)
                 case noteOff(channel: Int, note: Int)
                 case other }
    var format = 0, trackCount = 0, division = 0
    var events: [Event] = []
    var trackNames: [String] = []
    var tempoCount = 0, markerCount = 0, sysExCount = 0

    init(_ data: Data) throws {
        func be16(_ o: Int) -> Int { Int(data[o]) << 8 | Int(data[o + 1]) }
        func be32(_ o: Int) -> Int {
            Int(data[o]) << 24 | Int(data[o+1]) << 16 | Int(data[o+2]) << 8 | Int(data[o+3])
        }
        func varlen(_ o: inout Int) -> Int {
            var v = 0
            while true {
                let b = data[o]; o += 1
                v = (v << 7) | Int(b & 0x7F)
                if b & 0x80 == 0 { return v }
            }
        }
        struct Broken: Error { let reason: String }
        guard data.count > 14, data[0..<4].elementsEqual("MThd".utf8) else {
            throw Broken(reason: "kein MThd")
        }
        format = be16(8); trackCount = be16(10); division = be16(12)
        var o = 8 + be32(4)

        for track in 0..<trackCount {
            guard o + 8 <= data.count, data[o..<(o+4)].elementsEqual("MTrk".utf8) else {
                throw Broken(reason: "Spur \(track): kein MTrk")
            }
            let end = o + 8 + be32(o + 4)
            o += 8
            var status = 0
            while o < end {
                _ = varlen(&o)
                let b = Int(data[o])
                if b == 0xFF {
                    let type = Int(data[o + 1]); o += 2
                    let n = varlen(&o)
                    if type == 0x51 { tempoCount += 1 }
                    if type == 0x06 { markerCount += 1 }
                    if type == 0x03 {
                        trackNames.append(String(decoding: data[o..<(o+n)], as: UTF8.self))
                    }
                    o += n
                } else if b == 0xF0 || b == 0xF7 {
                    o += 1
                    let n = varlen(&o)
                    sysExCount += 1
                    o += n
                } else {
                    if b & 0x80 != 0 { status = b; o += 1 }
                    let high = status & 0xF0, channel = status & 0x0F
                    switch high {
                    case 0x90:
                        events.append(.noteOn(channel: channel, note: Int(data[o]),
                                              velocity: Int(data[o + 1]))); o += 2
                    case 0x80:
                        events.append(.noteOff(channel: channel, note: Int(data[o]))); o += 2
                    case 0xA0, 0xB0, 0xE0: events.append(.other); o += 2
                    case 0xC0, 0xD0:       events.append(.other); o += 1
                    default: throw Broken(reason: "unbekannter Status \(status)")
                    }
                }
            }
            guard o == end else { throw Broken(reason: "Spur \(track): Längenfehler") }
        }
        guard o == data.count else { throw Broken(reason: "Restbytes nach der letzten Spur") }
    }
}

@Test func variableLengthEncoding() {
    let file = MIDIFile(division: 960, tracks: [])
    #expect(Array(file.varLength(0)) == [0x00])
    #expect(Array(file.varLength(127)) == [0x7F])
    #expect(Array(file.varLength(128)) == [0x81, 0x00])
    #expect(Array(file.varLength(8192)) == [0xC0, 0x00])
    #expect(Array(file.varLength(0x0FFFFFFF)) == [0xFF, 0xFF, 0xFF, 0x7F])
}

@Test func writtenFilesAreWellFormed() throws {
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("med2midi-\(UUID().uuidString).mid")
        defer { try? FileManager.default.removeItem(at: target) }

        try MIDIExport.write(song: song, to: target)
        let reader = try SMFReader(Data(contentsOf: target))

        #expect(reader.format == 1)
        #expect(reader.division == Player.ppq)
        #expect(reader.trackCount >= 2)      // Tempospur plus mindestens eine
        #expect(reader.tempoCount >= 1)
        #expect(reader.markerCount >= 1)
    }
}

@Test func everyNoteIsSwitchedOffAgain() throws {
    for url in TestFiles.all {
        let song = try MEDLoader.load(file: url)
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("med2midi-\(UUID().uuidString).mid")
        defer { try? FileManager.default.removeItem(at: target) }
        try MIDIExport.write(song: song, to: target)
        let reader = try SMFReader(Data(contentsOf: target))

        var ons: [Int: Int] = [:], offs: [Int: Int] = [:]
        var zeroVelocity = 0
        for event in reader.events {
            switch event {
            case .noteOn(let channel, _, let velocity):
                ons[channel, default: 0] += 1
                if velocity == 0 { zeroVelocity += 1 }
            case .noteOff(let channel, _):
                offs[channel, default: 0] += 1
            case .other: break
            }
        }
        // Velocity 0 waere von einem Note-Off nicht zu unterscheiden.
        #expect(zeroVelocity == 0, "\(url.lastPathComponent): \(zeroVelocity) Noten mit Velocity 0")
        for channel in Set(ons.keys).union(offs.keys) {
            let message = "\(url.lastPathComponent) Kanal \(channel): "
                + "\(ons[channel] ?? 0) an, \(offs[channel] ?? 0) aus"
            #expect(ons[channel] == offs[channel], "\(message)")
        }
    }
}

@Test func sysExIsLeftOutByDefault() throws {
    guard let url = TestFiles.file("N_ich_will_neues.mmd1") else { return }
    let song = try MEDLoader.load(file: url)
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    let plain = folder.appendingPathComponent("med2midi-plain-\(UUID().uuidString).mid")
    let withSysEx = folder.appendingPathComponent("med2midi-sysex-\(UUID().uuidString).mid")
    defer {
        try? FileManager.default.removeItem(at: plain)
        try? FileManager.default.removeItem(at: withSysEx)
    }

    try MIDIExport.write(song: song, to: plain)
    #expect(try SMFReader(Data(contentsOf: plain)).sysExCount == 0)

    var options = MIDIExport.Options()
    options.embedSysEx = true
    try MIDIExport.write(song: song, to: withSysEx, options: options)
    // Ein Dump zerfaellt in 408 Einzelnachrichten, jede ein eigenes Ereignis.
    #expect(try SMFReader(Data(contentsOf: withSysEx)).sysExCount == 408)
}
