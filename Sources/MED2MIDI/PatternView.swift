import SwiftUI
import MEDKit

/// Tracker-Darstellung eines Blocks, so nah wie möglich an OctaMED.
///
/// Zellenformat aus einem Bildschirmfoto von OctaMED SoundStudio V1.03c
/// abgeleitet: Notenname (3 Zeichen), Instrument (eine Hexziffer),
/// Befehl (2) und Datenbyte (2) — zum Beispiel `E-5 A0000`.
struct PatternView: View {
    @Environment(Store.self) private var store
    @FocusState private var isFocused: Bool
    let song: Song
    let block: Block

    private let rowHeight: CGFloat = 16
    private let rowNumberWidth: CGFloat = 46
    private let trackWidth: CGFloat = 86

    /// Kopfzeile und Datenzeilen müssen exakt gleich breit sein, sonst
    /// zentriert die HStack im breiteren Fenster und die Spalten stehen
    /// versetzt.
    private var totalWidth: CGFloat {
        rowNumberWidth + trackWidth * CGFloat(block.tracks)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0,
                           pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(0..<block.rows, id: \.self) { row in
                            rowView(row)
                                .id(row)
                        }
                    } header: {
                        headerRow
                    }
                }
                .frame(width: totalWidth, alignment: .leading)
            }
                .onChange(of: store.position.row) { _, neu in
                    withAnimation(.linear(duration: 0.08)) {
                        proxy.scrollTo(neu, anchor: .center)
                    }
                }
            .onChange(of: store.position.block) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .background(Color.black)
        // Tastaturbedienung: die Ansicht muss fokussierbar sein, sonst
        // bekommt sie keine Tastendrücke.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onTapGesture { isFocused = true }
        .onKeyPress(.upArrow)    { store.moveRow(-1); return .handled }
        .onKeyPress(.downArrow)  { store.moveRow(1);  return .handled }
        .onKeyPress(.pageUp)     { store.moveRow(-store.pageStep); return .handled }
        .onKeyPress(.pageDown)   { store.moveRow(store.pageStep);  return .handled }
        .onKeyPress(.home)       { store.position.row = 0; return .handled }
        .onKeyPress(.end)        { store.position.row = max(0, block.rows - 1); return .handled }
        .onKeyPress(.leftArrow)  { store.stepInSongOrder(-1); return .handled }
        .onKeyPress(.rightArrow) { store.stepInSongOrder(1);  return .handled }
        .onKeyPress(.tab) {
            if block.pageCount > 1 {
                store.position.page = (store.position.page + 1) % block.pageCount
            }
            return .handled
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: rowNumberWidth)
            ForEach(0..<block.tracks, id: \.self) { track in
                VStack(spacing: 1) {
                    Text("\(track)")
                        .foregroundStyle(.secondary)
                    Text(trackInstrumentName(track))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(trackColour(track))
                        .lineLimit(1)
                }
                .frame(width: trackWidth)
            }
        }
        .frame(width: totalWidth, alignment: .leading)
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func rowView(_ row: Int) -> some View {
        let isCurrent = row == store.position.row
        let isBeat = song.rowsPerBeat > 0 && row % song.rowsPerBeat == 0
        return HStack(spacing: 0) {
            Text(String(format: "%03d", row))
                .foregroundStyle(isBeat ? .primary : .secondary)
                .frame(width: rowNumberWidth, alignment: .center)
            ForEach(0..<block.tracks, id: \.self) { track in
                cellView(row: row, track: track)
                    .frame(width: trackWidth, alignment: .leading)
            }
        }
        .frame(width: totalWidth, height: rowHeight, alignment: .leading)
        .background(
            isCurrent ? Color.accentColor.opacity(0.35)
                       : (isBeat ? Color.white.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { store.position.row = row; isFocused = true }
    }

    private func cellView(row: Int, track: Int) -> some View {
        let z = block.cell(row: row, track: track)
        let b = block.command(row: row, track: track, page: store.position.page)
        // Zelle ohne Note, aber mit Instrumentnummer: OctaMED zeichnet dort
        // ein senkrechtes Zeichen. Es ist keine Verzierung — jede solche
        // Zeile verlängert die klingende Note um eine Zeile.
        let haelt = z.note == 0 && z.instrument != 0
        return HStack(spacing: 0) {
            Text(haelt ? PatternRendering.holdGlyph : z.noteName)
                .foregroundStyle(z.note > 0 ? Color(nsColor: .white)
                                 : (haelt ? instrumentColour(z.instrument).opacity(0.7)
                                          : Color.gray.opacity(0.45)))
            Text(" ")
            Text(PatternRendering.instrumentDigit(z.instrument))
                .foregroundStyle(z.instrument > 0 ? instrumentColour(z.instrument)
                                                  : Color.gray.opacity(0.45))
            Text(b.hex)
                .foregroundStyle(commandColour(b))
        }
        .help(explanation(cell: z, command: b))
    }

    // MARK: - Erklärung beim Überfahren

    private func explanation(cell: Cell, command: Command) -> String {
        var parts: [String] = []
        if cell.note > 0 {
            parts.append("Note \(cell.noteName)")
        } else if cell.instrument > 0 {
            parts.append("Hält die klingende Note eine Zeile länger")
        }
        if cell.instrument > 0 {
            let i = instrument(cell.instrument)
            let name = i?.name.isEmpty == false ? " „\(i!.name)“" : ""
            let channel = i.map { $0.isMIDI ? "MIDI-Kanal \($0.midiChannel)" : "kein MIDI-Kanal" } ?? ""
            parts.append("Instrument \(cell.instrument)\(name) — \(channel)")
        }
        if !command.isEmpty {
            parts.append("\(command.hex): \(CommandCatalog.explanation(command))")
        }
        return parts.isEmpty ? "leer" : parts.joined(separator: "\n")
    }

    // MARK: - Farben

    private func instrument(_ number: UInt8) -> Instrument? {
        let i = Int(number) - 1
        return i >= 0 && i < song.instruments.count ? song.instruments[i] : nil
    }

    /// Welches Instrument prägt diese Spur? (häufigstes im Block)
    private func trackInstrument(_ track: Int) -> UInt8? {
        var counter: [UInt8: Int] = [:]
        for row in 0..<block.rows {
            let ins = block.cell(row: row, track: track).instrument
            if ins > 0 { counter[ins, default: 0] += 1 }
        }
        return counter.max { $0.value < $1.value }?.key
    }

    private func trackInstrumentName(_ track: Int) -> String {
        guard let nr = trackInstrument(track), let i = instrument(nr) else { return "—" }
        if !i.name.isEmpty { return i.name }
        return i.isMIDI ? "ch\(i.midiChannel)" : "#\(i.number)"
    }

    private func trackColour(_ track: Int) -> Color {
        guard let nr = trackInstrument(track) else { return .secondary }
        return instrumentColour(nr)
    }

    private static let palette: [Color] = [
        .init(red: 0.45, green: 0.78, blue: 1.00), .init(red: 0.98, green: 0.72, blue: 0.40),
        .init(red: 0.58, green: 0.87, blue: 0.60), .init(red: 0.96, green: 0.60, blue: 0.68),
        .init(red: 0.75, green: 0.68, blue: 0.98), .init(red: 0.52, green: 0.90, blue: 0.86),
        .init(red: 0.93, green: 0.85, blue: 0.48), .init(red: 0.86, green: 0.64, blue: 0.94),
    ]

    private func instrumentColour(_ number: UInt8) -> Color {
        guard store.colourTracks else { return Color(nsColor: .lightGray) }
        return Self.palette[Int(number) % Self.palette.count]
    }

    /// Befehle nach Wirkung einfärben — Lautstärke, Tonhöhe, Struktur, Rest.
    private func commandColour(_ b: Command) -> Color {
        if b.isEmpty { return Color.gray.opacity(0.35) }
        switch CommandCatalog.midiEffect(b.number) {
        case .velocity, .volumeController, .controllerValue, .controllerNumber,
             .pan, .modulationWheel, .assignableController:
            return .init(red: 0.55, green: 0.85, blue: 0.55)
        case .pitchBendUp, .pitchBendDown, .setPitchBend,
             .polyphonicAftertouch, .channelAftertouch:
            return .init(red: 0.95, green: 0.78, blue: 0.45)
        case .tempoOrSpecial, .ticksPerRow, .jumpToNextSequence,
             .playSequenceJump, .repeatRows, .repeatRow:
            return .init(red: 0.60, green: 0.75, blue: 1.00)
        case .sendSysEx, .midiPreset:
            return .init(red: 0.95, green: 0.55, blue: 0.95)
        case .unknown, .noEffectOnMIDI:
            return .init(red: 1.00, green: 0.45, blue: 0.45)
        default:
            return Color(nsColor: .lightGray)
        }
    }
}
