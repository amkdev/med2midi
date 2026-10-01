import Foundation

extension MEDLoader {
    /// Befehlsstatistik, Warnungen und Hinweise über alle Blöcke.
    static func analyse(blocks: [Block], instruments: [Instrument],
                         cmd3x: [(typ: UInt8, number: UInt16)],
                         volumeIsHex: Bool, sevenBit: Bool,
                         in diagnostics: inout Diagnostics) {
        var counts: [UInt8: Int] = [:]
        var locations: [UInt8: [SourceLocation]] = [:]
        var unknown: [UInt8: (count: Int, orte: [SourceLocation])] = [:]
        var withoutEffect: [UInt8: Int] = [:]
        var velocityValues: [UInt8: Int] = [:]
        var cmd3xMissing: Set<UInt8> = []
        var notesPerInstrument: [UInt8: Int] = [:]
        var valuesPerCommand: [UInt8: Set<UInt8>] = [:]

        for block in blocks {
            for row in 0..<block.rows {
                for track in 0..<block.tracks {
                    let z = block.cell(row: row, track: track)
                    if z.note > 0 && z.instrument > 0 {
                        notesPerInstrument[z.instrument, default: 0] += 1
                    }
                    for page in 0..<block.pageCount {
                        let b = block.command(row: row, track: track, page: page)
                        // Befehl 00 mit Datenbyte != 0 ist ein echter Befehl
                        // (MIDI-Controller-Wert) und darf nicht als leer gelten.
                        guard !b.isEmpty else { continue }

                        counts[b.number, default: 0] += 1
                        valuesPerCommand[b.number, default: []].insert(b.data)
                        let location = SourceLocation(block: block.number, blockname: block.name,
                                             row: row, track: track, page: page)
                        if locations[b.number, default: []].count < 8 {
                            locations[b.number, default: []].append(location)
                        }

                        switch CommandCatalog.midiEffect(b.number) {
                        case .unknown:
                            var e = unknown[b.number] ?? (0, [])
                            e.count += 1
                            if e.orte.count < 5 { e.orte.append(location) }
                            unknown[b.number] = e
                        case .noEffectOnMIDI:
                            withoutEffect[b.number, default: 0] += 1
                        case .velocity:
                            velocityValues[b.data, default: 0] += 1
                        case .assignableController:
                            if cmd3x.isEmpty { cmd3xMissing.insert(b.number) }
                        default: break
                        }
                    }
                }
            }
        }

        for (number, e) in unknown.sorted(by: { $0.key < $1.key }) {
            diagnostics.warnings.append(Warning(
                art: .unknownCommand(number: number, data: e.orte.first.map { _ in 0 } ?? 0),
                locations: e.orte, count: e.count))
        }
        for (number, count) in withoutEffect.sorted(by: { $0.key < $1.key }) {
            diagnostics.warnings.append(Warning(
                art: .commandWithoutMIDIEffect(number: number),
                locations: locations[number] ?? [], count: count))
        }
        for number in cmd3xMissing.sorted() {
            diagnostics.warnings.append(Warning(
                art: .cmd3xMissing(command: number),
                locations: locations[number] ?? [], count: counts[number] ?? 0))
        }
        // Werte ausserhalb 0–64 lassen den Befehl wirkungslos — die
        // Grundlautstärke des Instruments bleibt stehen. Am Original gemessen.
        // Im 7-Bit-Fall (Block mit Befehlserweiterung) gilt das nicht.
        let total = velocityValues.values.reduce(0, +)
        if total > 50, !sevenBit {
            let encoding: CommandCatalog.VolumeEncoding = volumeIsHex ? .hexadecimal : .decimal
            let withoutEffect = velocityValues
                .filter { CommandCatalog.volumeCommand(data: $0.key, encoding: encoding) == .ignored }
                .values.reduce(0, +)
            if withoutEffect > 0 {
                let percentage = withoutEffect * 100 / total
                if percentage >= 25 {
                    diagnostics.warnings.append(Warning(
                        art: .other("\(percentage) % der Velocity-Befehle (0C) liegen über 64 und "
                            + "bleiben wirkungslos — es gilt dort die Grundlautstärke des Instruments"),
                        locations: locations[0x0C] ?? [], count: withoutEffect))
                } else {
                    diagnostics.notices.append(Notice(
                        message: "\(percentage) % der Velocity-Befehle liegen über 64 "
                               + "und bleiben wirkungslos"))
                }
            }
        }

        // 0C ab 0x80 setzt die Grundlautstärke des Instruments statt einer
        // Notenlautstärke. In den Testdateien kommt das nicht vor.
        let defaultVolumeValues = velocityValues.filter { $0.key >= 0x80 }
        if !defaultVolumeValues.isEmpty {
            diagnostics.notices.append(Notice(
                message: "Befehl 0C mit Werten ab 0x80 (\(defaultVolumeValues.values.reduce(0, +))×): "
                    + "setzt die Grundlautstärke des Instruments, nicht die Note"))
        }

        // Kanalbelegung: Warnung nur bei zwei KLINGENDEN Instrumenten.
        // Ein Paar aus klingendem Instrument und einem mit Lautstärke 0
        // (vom Autor "MidiControlChannel_…" genannt) ist Absicht.
        var byChannel: [UInt8: [Instrument]] = [:]
        for i in instruments where i.isMIDI { byChannel[i.midiChannel, default: []].append(i) }
        for (channel, list) in byChannel.sorted(by: { $0.key < $1.key }) {
            let sounding = list.filter(\.sounds)
            if sounding.count > 1 {
                diagnostics.warnings.append(Warning(
                    art: .channelCollision(channel: channel, instruments: sounding.map(\.number)),
                    locations: [], count: sounding.count))
            } else if list.count > 1 {
                let silent = list.filter { !$0.sounds }.map { "#\($0.number) \($0.name)" }
                diagnostics.notices.append(Notice(
                    message: "Kanal \(channel): Controller-Spur(en) \(silent.joined(separator: ", ")) "
                        + "neben \(sounding.first.map { "#\($0.number) \($0.name)" } ?? "—")"))
            }
        }

        diagnostics.commandCounts = counts
        diagnostics.commandLocations = locations
    }
}
