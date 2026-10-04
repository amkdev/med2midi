import Foundation

/// Walks a song in playing order and produces a MIDI event list.
///
/// This is a simulation, not a player: nothing is sounded, only timed.
///
/// All behaviour here is measured on the original (OctaMED SoundStudio on an
/// Amiga, MIDI output recorded) or read from the play routine's 68k source.
/// See `docs/02-befehlskatalog.md`.
public struct Player {

    /// Ticks per quarter note of the produced event list. 960 keeps every
    /// row count that occurs (rowsPerBeat 4, 6, 8, 15) on whole ticks.
    public static let ppq = 960

    /// Added to a MED note number to get the MIDI note.
    ///
    /// **Unverified.** See `transposed(_:instrument:)` for the evidence that
    /// this is wrong; one measurement on the original settles it.
    public static let noteOffset = 35

    public struct Result: Sendable {
        public let events: [MIDIEvent]
        public let warnings: [String]
        /// Total length in ticks, including the trailing note-offs.
        public let lengthInTicks: Int
    }

    /// Per-track state the play routine keeps (`trk_*` in the assembler).
    struct TrackStateBox {
        var instrument: UInt8 = 0
        /// Note currently sounding, with the tick it started on.
        var sounding: (note: UInt8, channel: UInt8, instrument: UInt8, startTick: Int)?
        /// Tick at which the hold counter runs out; `nil` means unlimited.
        var holdExpiry: Int?
        /// Velocity set with command 0C; carried over until changed, like
        /// `trk_prevvol` in the assembler.
        var velocity: UInt8?
        /// Controller number chosen with command 05.
        ///
        /// Kept **per track**, not per channel. The manual says "Remember that
        /// each MIDI channel has its own controller number", which reads like
        /// a note about the receiving device rather than about OctaMED's own
        /// state. The data decides: in `sehnsuchts_blues.MMD1.pp` block 9 the
        /// `05 4A` sits in row 0 with no instrument, and the instrument that
        /// the following `00` values belong to only appears in row 1 on a
        /// different channel. Keyed per channel the filter sweep would have
        /// gone to the channel carried over from the previous block and never
        /// been heard — but it was.
        ///
        /// Not verifiable from the play routine: command 05 has no handler in
        /// the available source, its MIDI part having been removed.
        var controllerNumber: UInt8?
    }

    let song: Song
    let order: [Int]

    public init(song: Song) {
        self.song = song
        self.order = NoteAnalysis.songOrder(song)
    }

    public func run() -> Result {
        var events: [MIDIEvent] = []
        var warnings: [String] = []
        var tracks: [Int: TrackStateBox] = [:]
        var tick = 0
        var ticksPerRow = Self.ppq / max(song.rowsPerBeat, 1)
        var tempoValue = Int(song.defaultTempo)
        var ticksPerLine = Int(song.ticksPerRow)
        var stopped = false

        events.append(MIDIEvent(tick: 0, channel: nil,
                                kind: .tempo(microsecondsPerQuarter(tempo: tempoValue,
                                                                   ticksPerLine: ticksPerLine))))

        for (position, blockNumber) in order.enumerated() {
            if stopped { break }
            guard blockNumber < song.blocks.count else {
                warnings.append("Sequenzposition \(position) verweist auf Block \(blockNumber), "
                              + "den es nicht gibt")
                continue
            }
            let block = song.blocks[blockNumber]
            guard block.rows > 0 else { continue }

            let label = block.name.isEmpty ? "Block \(blockNumber)" : block.name
            events.append(MIDIEvent(tick: tick, channel: nil, kind: .marker(label)))

            for row in 0..<block.rows {
                if stopped { break }

                // Collect the row's commands across all pages first; a cell can
                // carry more than one.
                for track in 0..<block.tracks {
                    let cell = block.cell(row: row, track: track)
                    var state = tracks[track] ?? TrackStateBox()
                    if cell.instrument != 0 { state.instrument = cell.instrument }
                    tracks[track] = state

                    let location = SourceLocation(block: blockNumber, blockname: block.name,
                                                  row: row, track: track, page: 0)
                    let instrument = instrumentFor(tracks[track]?.instrument ?? 0)

                    for page in 0..<block.pageCount {
                        let command = block.command(row: row, track: track, page: page)
                        guard !command.isEmpty else { continue }
                        apply(command: command, cell: cell, track: track,
                              block: block,
                              instrument: instrument, at: tick, location: location,
                              events: &events, tracks: &tracks,
                              warnings: &warnings,
                              tempoValue: &tempoValue, ticksPerLine: &ticksPerLine,
                              stopped: &stopped)
                    }

                    // The note itself is played after the row's commands, so a
                    // velocity set in the same cell applies to it. The play
                    // routine reads the whole cell before sounding the note.
                    if cell.note > 0, let instrument, instrument.isMIDI {
                        startNote(cell: cell, track: track, instrument: instrument,
                                  block: block, row: row, at: tick, location: location,
                                  ticksPerRow: ticksPerRow, ticksPerLine: ticksPerLine,
                                  events: &events, tracks: &tracks)
                    }
                }

                // Expire held notes that run out during this row.
                releaseExpired(upTo: tick + ticksPerRow, events: &events, tracks: &tracks)
                tick += ticksPerRow
            }
        }

        // Anything still sounding at the end has to be released.
        for (track, state) in tracks.sorted(by: { $0.key < $1.key }) {
            guard let sounding = state.sounding else { continue }
            events.append(MIDIEvent(tick: tick, channel: sounding.channel,
                                    kind: .noteOff(note: sounding.note),
                                    instrument: Int(sounding.instrument)))
            warnings.append("Spur \(track): \(noteName(sounding.note)) klang am Songende noch "
                          + "und wurde beendet")
            tracks[track]?.sounding = nil
        }

        events.sort { $0.tick != $1.tick ? $0.tick < $1.tick : $0.order < $1.order }
        return Result(events: events, warnings: warnings, lengthInTicks: tick)
    }

    // MARK: - Helpers

    func instrumentFor(_ number: UInt8) -> Instrument? {
        let index = Int(number) - 1
        return index >= 0 && index < song.instruments.count ? song.instruments[index] : nil
    }

    /// Microseconds per quarter note.
    ///
    /// A quarter is `rowsPerBeat` rows long, so
    /// `µs = rowsPerBeat × rowDuration × 1e6`. In BPM mode this reduces to
    /// `ticksPerLine × 10⁷ / tempo` — note that OctaMED's BPM only equals the
    /// musical tempo when ticksPerLine is 6.
    func microsecondsPerQuarter(tempo: Int, ticksPerLine: Int) -> Int {
        let rows = max(song.rowsPerBeat, 1)
        if song.bpmMode, tempo > 0 {
            return Int((Double(ticksPerLine) * 10_000_000.0 / Double(tempo)).rounded())
        }
        // SPD mode: derive from the CIA timer period.
        guard tempo > 10 else { return 500_000 }
        let period = (Timing.timerDiv / Double(tempo)).rounded(.down)
        let tick = period / Timing.ciaClockPAL
        return Int((tick * Double(ticksPerLine) * Double(rows) * 1_000_000).rounded())
    }

    func noteName(_ note: UInt8) -> String {
        Cell(note: note, instrument: 0, command: Command(number: 0, data: 0)).noteName
    }
}
