import Foundation

/// One MIDI event at an absolute position on the tick grid.
///
/// Ticks are musical: a row is `ppq / rowsPerBeat` ticks, so the grid stays
/// stable while tempo meta events carry the speed. Tempo changes therefore do
/// not shift any note.
public struct MIDIEvent: Sendable {
    public enum Kind: Sendable, Equatable {
        case noteOn(note: UInt8, velocity: UInt8)
        case noteOff(note: UInt8)
        case controlChange(controller: UInt8, value: UInt8)
        /// −8192 … 8191, centre 0.
        case pitchBend(Int16)
        case channelPressure(UInt8)
        case polyPressure(note: UInt8, value: UInt8)
        case programChange(UInt8)
        case sysEx([UInt8])
        /// Microseconds per quarter note.
        case tempo(Int)
        case marker(String)
    }

    public let tick: Int
    /// 1…16 as stored in MED, `nil` for meta events.
    public let channel: UInt8?
    public let kind: Kind
    /// MED instrument number, used to assign the event to an export track.
    public let instrument: Int?
    /// Where this came from in the pattern — lets every exported event be
    /// traced back to a cell.
    public let source: SourceLocation?

    public init(tick: Int, channel: UInt8?, kind: Kind,
                instrument: Int? = nil, source: SourceLocation? = nil) {
        self.tick = tick
        self.channel = channel
        self.kind = kind
        self.instrument = instrument
        self.source = source
    }

    /// Dasselbe Ereignis an einer anderen Stelle der Zeitachse.
    public func moved(to tick: Int) -> MIDIEvent {
        MIDIEvent(tick: tick, channel: channel, kind: kind,
                  instrument: instrument, source: source)
    }

    /// Sorting rank within one tick: note-offs before note-ons so a repeated
    /// note on the same key does not cut its own successor; meta first.
    var order: Int {
        switch kind {
        case .tempo, .marker:   return 0
        case .noteOff:          return 1
        case .sysEx:            return 2
        case .programChange:    return 3
        case .controlChange, .pitchBend, .channelPressure, .polyPressure: return 4
        case .noteOn:           return 5
        }
    }
}
