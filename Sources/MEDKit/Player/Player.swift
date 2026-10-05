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
    /// **Measured on the original** (2026-10-04): a `C-2` in the pattern, with
    /// song and instrument transpose at zero, arrived as `C-1` in MIDI Monitor
    /// with its note format set to "Middle C = C3" — that is MIDI note 12.
    /// `C-2` is MED note 13, so the offset is −1: MED note 1 maps to MIDI 0.
    ///
    /// OctaMED simply names its octaves one higher than MIDI Monitor does;
    /// the numbers pass through nearly unchanged.
    ///
    /// Cross-check on the real songs: with this offset the instruments land
    /// where they belong — OrganBass 24–48, Piano 36–86, Trumpet 64–72. The
    /// very low notes in the material all belong to the author's silent
    /// `MidiControlChannel_…` lanes, whose notes only set the channel context.
    public static let noteOffset = -1

    public struct Result: Sendable {
        public let events: [MIDIEvent]
        public let warnings: [String]
        /// Total length in ticks, including the trailing note-offs.
        public let lengthInTicks: Int
        /// Wo jeder Eintrag der Songreihenfolge beginnt und endet.
        public let spans: [BlockSpan]
    }

    /// Ein Eintrag der Songreihenfolge mit seiner Lage auf der Zeitachse.
    public struct BlockSpan: Sendable {
        public let position: Int
        public let block: Int
        public let name: String
        public let startTick: Int
        public let endTick: Int
        public let rows: Int
    }

    /// Per-track state the play routine keeps (`trk_*` in the assembler).
    struct TrackStateBox {
        var instrument: UInt8 = 0
        /// Note currently sounding, with the tick it started on.
        var sounding: (note: UInt8, channel: UInt8, instrument: UInt8, startTick: Int)?
        /// Tick at which the hold counter runs out; `nil` means unlimited.
        var holdExpiry: Int?
        /// Current velocity, mirroring `trk_prevvol` in the assembler.
        ///
        /// Set from the instrument's default volume by every cell that carries
        /// an instrument number, and overwritten by command 0C for the rows
        /// that follow until the next instrument number.
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

    /// Blöcke überspringen, die nur einen SysEx-Dump abschicken.
    ///
    /// Ihre Länge ist die Ladezeit des MU80, nicht Musik. Der Dump selbst
    /// geht trotzdem hinaus, nur ohne die Wartezeit davor.
    public var skipSysExBlocks: Bool

    public init(song: Song, skipSysExBlocks: Bool = true) {
        self.song = song
        self.order = NoteAnalysis.songOrder(song)
        self.skipSysExBlocks = skipSysExBlocks
    }

    public func run() -> Result {
        var events: [MIDIEvent] = []
        var warnings: [String] = []
        var tracks: [Int: TrackStateBox] = [:]
        // Grundlautstärken, die ein `0C` mit gesetztem höchsten Bit zur
        // Laufzeit überschrieben hat — siehe `defaultVolume(of:overrides:)`.
        var defaultVolumes: [Int: UInt8] = [:]
        var tick = 0
        var ticksPerRow = Self.ppq / max(song.rowsPerBeat, 1)
        var tempoValue = Int(song.defaultTempo)
        var ticksPerLine = Int(song.ticksPerRow)
        var stopped = false
        var spans: [BlockSpan] = []

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

            // Sendeblock: Dump abschicken, aber keine Zeit verstreichen lassen.
            if skipSysExBlocks, block.isSysExSendBlock {
                for row in 0..<block.rows {
                    for track in 0..<block.tracks {
                        for page in 0..<block.pageCount {
                            let command = block.command(row: row, track: track, page: page)
                            guard command.number == 0x10 else { continue }
                            let location = SourceLocation(block: blockNumber,
                                                          blockname: block.name,
                                                          row: row, track: track, page: page)
                            let index = Int(command.data)
                            guard index < song.dumps.count else {
                                warnings.append("\(location): Befehl 10 verweist auf Dump "
                                              + "\(index), den es nicht gibt")
                                continue
                            }
                            let dump = song.dumps[index]
                            events.append(MIDIEvent(tick: tick, channel: nil,
                                                    kind: .sysEx(dump.rawData), source: location))
                            events.append(MIDIEvent(tick: tick, channel: nil,
                                kind: .marker("SysEx: " + (dump.name.isEmpty
                                                           ? "Dump \(index)" : dump.name)),
                                source: location))
                        }
                    }
                }
                continue
            }

            events.append(MIDIEvent(tick: tick, channel: nil, kind: .marker(label)))
            let spanStart = tick

            for row in 0..<block.rows {
                if stopped { break }

                // Collect the row's commands across all pages first; a cell can
                // carry more than one.
                for track in 0..<block.tracks {
                    let cell = block.cell(row: row, track: track)

                    // Erst die Hold-Verlängerung: Die Abspielroutine prüft sie
                    // beim Zeilenwechsel, bevor die Zeile gespielt wird.
                    extendHold(cell: cell, track: track, at: tick,
                               ticksPerRow: ticksPerRow, tracks: &tracks)

                    var state = tracks[track] ?? TrackStateBox()
                    if cell.instrument != 0 {
                        state.instrument = cell.instrument
                        // A cell carrying an instrument number resets the track
                        // volume to that instrument's default. In the play
                        // routine this happens in the instrument loop, before
                        // the effects run:
                        //
                        //     MOVE.B inst_svol(A0),trk_prevvol(A5)  ;vol of this instr
                        //
                        // Command 0C writes `trk_prevvol` afterwards, in
                        // DoPreFXLoop, and the note is sounded after that. A
                        // velocity therefore reaches only the notes up to the
                        // next instrument number — it is not carried through
                        // the song.
                        state.velocity = instrumentFor(cell.instrument)
                            .map { defaultVolume(of: $0, overrides: defaultVolumes) }
                    }
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
                              warnings: &warnings, defaultVolumes: &defaultVolumes,
                              tempoValue: &tempoValue, ticksPerLine: &ticksPerLine,
                              stopped: &stopped)
                    }

                    // The note itself is played after the row's commands, so a
                    // velocity set in the same cell applies to it. The play
                    // routine reads the whole cell before sounding the note.
                    // Auch Sample-Instrumente bekommen Noten. Sie klingen
                    // nicht über MIDI — der Amiga hat sie selbst erzeugt —,
                    // aber die Noten sind Musik und gehören in den Export.
                    // Mit dem Sample aus `samples/` in einem Sampler der DAW
                    // ergibt die Spur wieder das, was sie war.
                    if cell.note > 0, let instrument,
                       instrument.isMIDI || hasSample(instrument) {
                        startNote(cell: cell, track: track, instrument: instrument,
                                  at: tick, location: location,
                                  ticksPerRow: ticksPerRow, ticksPerLine: ticksPerLine,
                                  events: &events, tracks: &tracks)
                    }
                }

                // Expire held notes that run out during this row.
                releaseExpired(upTo: tick + ticksPerRow, events: &events, tracks: &tracks)
                tick += ticksPerRow
            }

            spans.append(BlockSpan(position: position, block: blockNumber, name: label,
                                   startTick: spanStart, endTick: tick,
                                   rows: (tick - spanStart) / max(ticksPerRow, 1)))
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

        // Stabil sortieren. Swifts `sort` ist es nicht: Bei gleichem Tick und
        // gleichem Rang darf es die Reihenfolge frei wählen, und es tut das
        // auch — zwei Läufe desselben Binärstands lieferten unterschiedliche
        // Dateien. Die Eingangsreihenfolge als letztes Kriterium macht die
        // Ordnung total und den Export damit reproduzierbar.
        events = events.enumerated()
            .sorted { a, b in
                if a.element.tick != b.element.tick { return a.element.tick < b.element.tick }
                if a.element.order != b.element.order { return a.element.order < b.element.order }
                return a.offset < b.offset
            }
            .map(\.element)
        return Result(events: events, warnings: warnings, lengthInTicks: tick, spans: spans)
    }

    // MARK: - Helpers

    /// Grundlautstärke eines Instruments als MIDI-Velocity.
    ///
    /// Normalerweise die aus der Datei. Ein `0C` mit gesetztem höchsten Bit
    /// schreibt aber in die Instrumententabelle selbst
    ///
    ///     MOVE.B D0,inst_svol(A4,D1.W)  ;set new svol
    ///
    /// und gilt damit für alle späteren Noten des Instruments, nicht nur für
    /// die eigene Spur. In den sieben vorliegenden Dateien kommt das kein
    /// einziges Mal vor (22 046 `0C`-Befehle, davon 0 mit gesetztem Bit) —
    /// abgebildet ist es trotzdem, damit es nicht stillschweigend fehlt.
    func defaultVolume(of instrument: Instrument, overrides: [Int: UInt8]) -> UInt8 {
        if let svol = overrides[instrument.number] {
            return CommandCatalog.midiVolume(ausSvol: svol)
        }
        return instrument.initialMIDIVolume
    }

    /// Ob zu diesem Instrument Sampledaten in der Datei liegen.
    func hasSample(_ instrument: Instrument) -> Bool {
        song.samples.contains { $0.instrument == instrument.number && !$0.data.isEmpty }
    }

    /// Kanal für ein Sample-Instrument.
    ///
    /// Sample-Instrumente haben keinen MIDI-Kanal — der Amiga hat sie selbst
    /// erzeugt. Für die Datei braucht es trotzdem einen, und welcher es ist,
    /// bedeutet nichts: Jedes Sample-Instrument bekommt eine eigene Spur, und
    /// die DAW legt je Spur ein Instrument an. Kanal 1 ist die ruhigste Wahl.
    static let sampleChannel: UInt8 = 1

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
