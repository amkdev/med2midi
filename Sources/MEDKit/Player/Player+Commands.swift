import Foundation

extension Player {

    /// Starts a note and works out when it ends.
    ///
    /// Length, measured on the original:
    /// `hold rows × row + hold × tick`, where the hold rows are the cells below
    /// that carry only the instrument number. `hold == 0` means unlimited — the
    /// note then runs until `0F FF` or the next note on the track.
    /// See `Timing.noteDuration`.
    func startNote(cell: Cell, track: Int, instrument: Instrument,
                   block: Block, row: Int, at tick: Int, location: SourceLocation,
                   ticksPerRow: Int, ticksPerLine: Int,
                   events: inout [MIDIEvent], tracks: inout [Int: TrackStateBox]) {
        var state = tracks[track] ?? TrackStateBox()

        // A new note on the same track ends the previous one.
        if let sounding = state.sounding {
            events.append(MIDIEvent(tick: tick, channel: sounding.channel,
                                    kind: .noteOff(note: sounding.note),
                                    instrument: Int(sounding.instrument), source: location))
        }

        let channel = instrument.midiChannel
        let note = transposed(cell.note, instrument: instrument)
        guard let note else {
            state.sounding = nil
            tracks[track] = state
            return
        }

        let velocity = state.velocity ?? instrument.initialMIDIVolume

        // Velocity 0 sounds nothing. The author's silent `MidiControlChannel_…`
        // instruments have svol 0 and only exist to give the following
        // controller commands a channel — their notes must not reach the file,
        // where they would be indistinguishable from note-offs.
        guard velocity > 0 else {
            state.sounding = nil
            state.holdExpiry = nil
            tracks[track] = state
            return
        }

        events.append(MIDIEvent(tick: tick, channel: channel,
                                kind: .noteOn(note: note, velocity: velocity),
                                instrument: instrument.number, source: location))

        let hold = instrument.hold ?? 0
        if hold == 0 {
            state.holdExpiry = nil                       // unlimited
        } else {
            let holdRows = block.holdRows(afterRow: row, track: track)
            let ticks = holdRows * ticksPerRow
                      + Int((Double(hold) / Double(ticksPerLine) * Double(ticksPerRow)).rounded())
            state.holdExpiry = tick + max(ticks, 1)
        }
        state.sounding = (note, channel, instrument.number == 0 ? 0 : UInt8(instrument.number), tick)
        tracks[track] = state
    }

    /// Emits note-offs for every note whose hold has run out before `limit`.
    func releaseExpired(upTo limit: Int,
                        events: inout [MIDIEvent], tracks: inout [Int: TrackStateBox]) {
        for (track, state) in tracks {
            guard let sounding = state.sounding, let expiry = state.holdExpiry,
                  expiry < limit else { continue }
            events.append(MIDIEvent(tick: max(expiry, sounding.startTick + 1),
                                    channel: sounding.channel,
                                    kind: .noteOff(note: sounding.note),
                                    instrument: Int(sounding.instrument),
                                    source: SourceLocation(block: -1, blockname: "",
                                                           row: 0, track: track, page: 0)))
            tracks[track]?.sounding = nil
            tracks[track]?.holdExpiry = nil
        }
    }

    /// Note number after song and instrument transpose.
    ///
    /// **The octave offset is not yet verified.** The value 35 here is a guess
    /// (MED note 1 = C-1 mapped to MIDI 36). Evidence against it: in the
    /// author's hold test the pattern held `C-2` and MIDI Monitor logged
    /// `C-1`, which no reading of a +35 offset produces. The resulting note
    /// range of MIDI 46–127 with hits at the very top also looks too high.
    ///
    /// To settle it: play a single `C-2` with transpose 0 on both song and
    /// instrument, and read the note **number** off MIDI Monitor.
    /// `Player.noteOffset` is the one place to change.
    func transposed(_ note: UInt8, instrument: Instrument) -> UInt8? {
        guard note > 0 else { return nil }
        let value = Int(note) + Player.noteOffset
            + Int(instrument.transpose) + Int(song.songTranspose)
        return (0...127).contains(value) ? UInt8(value) : nil
    }

    /// Applies one command of a cell.
    func apply(command: Command, cell: Cell, track: Int, block: Block,
               instrument: Instrument?, at tick: Int, location: SourceLocation,
               events: inout [MIDIEvent], tracks: inout [Int: TrackStateBox],
               warnings: inout [String],
               tempoValue: inout Int, ticksPerLine: inout Int, stopped: inout Bool) {

        let channel = instrument?.midiChannel ?? 0
        func emit(_ kind: MIDIEvent.Kind) {
            events.append(MIDIEvent(tick: tick, channel: channel, kind: kind,
                                    instrument: instrument?.number, source: location))
        }
        let isMIDI = instrument?.isMIDI == true

        switch CommandCatalog.midiEffect(command.number) {

        case .velocity:
            switch CommandCatalog.volumeCommand(data: command.data,
                                                encoding: encoding(for: block)) {
            case .velocity(let v):          tracks[track, default: TrackStateBox()].velocity = v
            case .setDefaultVolume(let v):  tracks[track, default: TrackStateBox()].velocity =
                                                CommandCatalog.midiVolume(ausSvol: v)
            case .ignored:                  break      // previous volume stands
            }

        case .volumeController:
            guard isMIDI else { break }
            emit(.controlChange(controller: 7, value: min(command.data, 127)))

        case .pan:
            guard isMIDI else { break }
            emit(.controlChange(controller: 10, value: min(command.data, 127)))

        case .modulationWheel:
            guard isMIDI else { break }
            emit(.controlChange(controller: 1, value: min(command.data, 127)))

        case .controllerNumber:
            tracks[track, default: TrackStateBox()].controllerNumber = command.data & 0x7F

        case .controllerValue:
            guard isMIDI, command.data != 0 else { break }
            guard let number = tracks[track]?.controllerNumber else {
                warnings.append("\(location): Controller-Wert ohne vorherige Nummer (Befehl 05)")
                break
            }
            // The manual: level 0x80 means value 0, because 0000 is "no command".
            let value: UInt8 = command.data == 0x80 ? 0 : min(command.data, 127)
            emit(.controlChange(controller: number, value: value))

        case .assignableController(let index):
            guard isMIDI else { break }
            guard index < song.cmd3xControllers.count else {
                warnings.append("\(location): Befehl \(String(format: "%02X", command.number)) "
                              + "ohne Eintrag in der Cmd3x-Tabelle")
                break
            }
            let setting = song.cmd3xControllers[index]
            guard setting.typ == 0 else {
                warnings.append("\(location): Cmd3x-Typ \(setting.typ) (RPN/NRPN) "
                              + "wird noch nicht umgesetzt")
                break
            }
            emit(.controlChange(controller: UInt8(setting.number & 0x7F),
                                value: min(command.data, 127)))

        case .channelAftertouch:
            guard isMIDI else { break }
            emit(.channelPressure(min(command.data, 127)))

        case .polyphonicAftertouch:
            guard isMIDI, let sounding = tracks[track]?.sounding else { break }
            emit(.polyPressure(note: sounding.note, value: min(command.data, 127)))

        case .pitchBendUp, .pitchBendDown, .setPitchBend:
            guard isMIDI else { break }
            emit(.pitchBend(pitchBendValue(command)))

        case .midiPreset:
            guard isMIDI else { break }
            emit(.programChange(min(command.data, 127)))

        case .sendSysEx:
            let index = Int(command.data)
            guard index < song.dumps.count else {
                warnings.append("\(location): Befehl 10 verweist auf Dump \(index), "
                              + "den es nicht gibt")
                break
            }
            events.append(MIDIEvent(tick: tick, channel: nil,
                                    kind: .sysEx(song.dumps[index].rawData), source: location))
            events.append(MIDIEvent(tick: tick, channel: nil,
                                    kind: .marker("SysEx: " + (song.dumps[index].name.isEmpty
                                        ? "Dump \(index)" : song.dumps[index].name))))

        case .ticksPerRow:
            guard command.data >= 1, command.data <= 0x20 else { break }
            ticksPerLine = Int(command.data)
            events.append(MIDIEvent(tick: tick, channel: nil,
                                    kind: .tempo(microsecondsPerQuarter(tempo: tempoValue,
                                                                       ticksPerLine: ticksPerLine)),
                                    source: location))

        case .tempoOrSpecial:
            applyTempoCommand(command, track: track, at: tick, location: location,
                              events: &events, tracks: &tracks, warnings: &warnings,
                              tempoValue: &tempoValue, ticksPerLine: ticksPerLine,
                              stopped: &stopped)

        case .setHold, .noEffectOnMIDI:
            break

        case .repeatRows, .repeatRow, .jumpToNextSequence, .playSequenceJump,
             .delayOrRetrigger:
            warnings.append("\(location): Befehl \(String(format: "%02X", command.number)) "
                          + "greift in den Ablauf ein und wird noch nicht umgesetzt — "
                          + "die Zeitachse ab hier kann abweichen")

        case .unknown:
            warnings.append("\(location): unbekannter Befehl "
                          + String(format: "%02X%02X", command.number, command.data))
        }
    }

    private func applyTempoCommand(_ command: Command, track: Int, at tick: Int,
                                   location: SourceLocation,
                                   events: inout [MIDIEvent], tracks: inout [Int: TrackStateBox],
                                   warnings: inout [String],
                                   tempoValue: inout Int, ticksPerLine: Int,
                                   stopped: inout Bool) {
        switch TempoSpecial(data: command.data) {
        case .stopNote:
            guard let sounding = tracks[track]?.sounding else { break }
            events.append(MIDIEvent(tick: tick, channel: sounding.channel,
                                    kind: .noteOff(note: sounding.note),
                                    instrument: Int(sounding.instrument), source: location))
            tracks[track]?.sounding = nil
            tracks[track]?.holdExpiry = nil

        case .stopSong:
            stopped = true

        case .setTempo(let value):
            guard value > 0 else {
                warnings.append("\(location): Befehl 0F00 ist ein Pattern Break und wird "
                              + "noch nicht umgesetzt")
                break
            }
            tempoValue = Int(value)
            events.append(MIDIEvent(tick: tick, channel: nil,
                                    kind: .tempo(microsecondsPerQuarter(tempo: tempoValue,
                                                                       ticksPerLine: ticksPerLine)),
                                    source: location))

        case .holdPedalOn, .holdPedalOff:
            let value: UInt8 = TempoSpecial(data: command.data) == .holdPedalOn ? 127 : 0
            if let instrument = instrumentFor(tracks[track]?.instrument ?? 0), instrument.isMIDI {
                events.append(MIDIEvent(tick: tick, channel: instrument.midiChannel,
                                        kind: .controlChange(controller: 64, value: value),
                                        instrument: instrument.number, source: location))
            }

        case .retriggerTwice, .retriggerThreeTimes,
             .delayHalfRow, .delayOneThirdRow, .delayTwoThirdsRow:
            warnings.append("\(location): \(String(format: "0F%02X", command.data)) "
                          + "verzögert oder wiederholt die Note und wird noch nicht umgesetzt")

        case .waitUntilSent:
            break   // only relevant for the Amiga's serial port
        }
    }

    /// Pitch bend from commands 01/02/03/13.
    ///
    /// The manual: 03 and 13 set an absolute value, "expressed as a signed
    /// hexadecimal digit", 0x00 centre and 0x80 the lowest value. Commands
    /// 01/02 slide per tick; that is not modelled yet, the value is taken as
    /// a one-off setting.
    private func pitchBendValue(_ command: Command) -> Int16 {
        let signed = Int(Int8(bitPattern: command.data))
        return Int16(max(-8192, min(8191, signed * 64)))
    }

    /// Which reading applies to a `0C` value. Per block: a block carrying a
    /// command extension uses 7-bit volumes.
    func encoding(for block: Block?) -> CommandCatalog.VolumeEncoding {
        if let block, block.sevenBitVolume { return .sevenBit }
        if song.blocks.contains(where: \.sevenBitVolume) { return .sevenBit }
        return song.volumeIsHex ? .hexadecimal : .decimal
    }
}
