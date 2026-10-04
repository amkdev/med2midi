import Foundation

/// Renders an event list as text, so every exported event can be checked
/// against the pattern view without opening a DAW.
public enum EventListing {

    public static func text(for result: Player.Result, song: Song,
                            limit: Int = 60) -> String {
        var out: [String] = []
        out.append("\(song.fileName) — \(result.events.count) Ereignisse, "
                 + "\(result.lengthInTicks) Ticks "
                 + "(\(String(format: "%.1f", seconds(result, song: song))) s)")
        out.append(String(repeating: "─", count: 96))
        out.append(String(format: "%-10@ %-7@ %-5@ %-34@ %@",
                          "Tick" as NSString, "Takt" as NSString, "Kan" as NSString,
                          "Ereignis" as NSString, "Fundstelle" as NSString))
        out.append(String(repeating: "─", count: 96))

        for event in result.events.prefix(limit) {
            let bar = barPosition(tick: event.tick, song: song)
            let channel = event.channel.map { String(format: "%2d", $0) } ?? " —"
            out.append(String(format: "%-10d %-7@ %-5@ %-34@ %@",
                              event.tick, bar as NSString, channel as NSString,
                              describe(event.kind) as NSString,
                              (event.source?.description ?? "") as NSString))
        }
        if result.events.count > limit {
            out.append("… \(result.events.count - limit) weitere")
        }
        if !result.warnings.isEmpty {
            out.append("")
            out.append("Warnungen:")
            for w in result.warnings.prefix(20) { out.append("  • \(w)") }
            if result.warnings.count > 20 {
                out.append("  … \(result.warnings.count - 20) weitere")
            }
        }
        return out.joined(separator: "\n")
    }

    /// Statistics instead of a full dump — useful for a quick sanity check.
    public static func summary(for result: Player.Result, song: Song) -> String {
        var counts: [String: Int] = [:]
        var notes = 0, lowest = 127, highest = 0
        for event in result.events {
            counts[label(event.kind), default: 0] += 1
            if case .noteOn(let note, _) = event.kind {
                notes += 1
                lowest = min(lowest, Int(note))
                highest = max(highest, Int(note))
            }
        }
        var out = ["\(song.fileName)",
                   "  Dauer        : \(String(format: "%.1f", seconds(result, song: song))) s"
                 + "  (\(result.lengthInTicks) Ticks)"]
        for (kind, n) in counts.sorted(by: { $0.key < $1.key }) {
            out.append(String(format: "  %-13@: %d", kind as NSString, n))
        }
        if notes > 0 {
            out.append("  Tonumfang    : MIDI \(lowest)–\(highest)")
        }
        out.append("  Warnungen    : \(result.warnings.count)")
        return out.joined(separator: "\n")
    }

    // MARK: - Helpers

    static func seconds(_ result: Player.Result, song: Song) -> Double {
        // Walk the tempo events so changes are taken into account.
        var seconds = 0.0
        var lastTick = 0
        var microsecondsPerQuarter = 500_000.0
        for event in result.events {
            if case .tempo(let value) = event.kind {
                seconds += Double(event.tick - lastTick) / Double(Player.ppq)
                         * microsecondsPerQuarter / 1_000_000
                lastTick = event.tick
                microsecondsPerQuarter = Double(value)
            }
        }
        seconds += Double(result.lengthInTicks - lastTick) / Double(Player.ppq)
                 * microsecondsPerQuarter / 1_000_000
        return seconds
    }

    static func barPosition(tick: Int, song: Song) -> String {
        let beats = tick / Player.ppq
        let rest = tick % Player.ppq
        let sixteenth = rest * 4 / Player.ppq
        return "\(beats + 1).\(sixteenth + 1)"
    }

    static func label(_ kind: MIDIEvent.Kind) -> String {
        switch kind {
        case .noteOn:          return "Note On"
        case .noteOff:         return "Note Off"
        case .controlChange:   return "Controller"
        case .pitchBend:       return "Pitchbend"
        case .channelPressure: return "Aftertouch"
        case .polyPressure:    return "Poly-AT"
        case .programChange:   return "Programm"
        case .sysEx:           return "SysEx"
        case .tempo:           return "Tempo"
        case .marker:          return "Marker"
        }
    }

    static func describe(_ kind: MIDIEvent.Kind) -> String {
        switch kind {
        case .noteOn(let n, let v):     return "Note On  \(name(n)) vel \(v)"
        case .noteOff(let n):           return "Note Off \(name(n))"
        case .controlChange(let c, let v): return "CC\(c) = \(v)"
        case .pitchBend(let v):         return "Pitchbend \(v)"
        case .channelPressure(let v):   return "Aftertouch \(v)"
        case .polyPressure(let n, let v): return "Poly-AT \(name(n)) \(v)"
        case .programChange(let p):     return "Programm \(p)"
        case .sysEx(let bytes):         return "SysEx \(bytes.count) Bytes"
        case .tempo(let us):
            return String(format: "Tempo %.1f BPM", 60_000_000.0 / Double(us))
        case .marker(let text):         return "Marker „\(text)“"
        }
    }

    static func name(_ midiNote: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[Int(midiNote) % 12])\(Int(midiNote) / 12 - 1)"
    }
}
