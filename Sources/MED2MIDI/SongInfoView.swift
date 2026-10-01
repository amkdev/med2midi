import SwiftUI
import MEDKit

struct SongInfoView: View {
    @Environment(Store.self) private var store
    let song: Song

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Allgemein") {
                    row("Format", song.version.name)
                    row("Songname", song.name.isEmpty ? "—" : song.name)
                    row("Datei", "\(song.fileName)  ·  \(song.fileSize) Bytes")
                    row("modlen", "\(song.modlen)"
                        + (Int(song.modlen) == song.fileSize ? "  (= Dateigröße)" : "  ⚠︎ weicht ab"))
                    if song.extraSongs > 0 {
                        row("Multi-Modul", "\(song.extraSongs + 1) Songs in der Datei")
                    }
                }
                section("Tempo") {
                    row("Tempo", song.bpmMode ? "\(song.defaultTempo) BPM"
                                                 : "\(song.defaultTempo) (Tracker-Tempo)")
                    row("Ticks pro Zeile", "\(song.ticksPerRow)")
                    row("Zeilen pro Beat", "\(song.rowsPerBeat)")
                    row("Transponierung", "\(song.songTranspose)")
                    row("Mixing-Modus", song.mixingMode ? "ja" : "nein")
                }
                section("Struktur") {
                    row("Blöcke", "\(song.blocks.count)")
                    if song.version.hasSections {
                        row("Sections", song.sections.map(String.init).joined(separator: ", "))
                    }
                    ForEach(Array(song.playSequences.enumerated()), id: \.offset) { i, p in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name.isEmpty ? "Playsequenz \(i)" : "Playsequenz \(i): \(p.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            FlowLayout(spacing: 4) {
                                ForEach(Array(p.blocks.enumerated()), id: \.offset) { j, nr in
                                    Button {
                                        store.position.sequencePosition = j
                                        store.goToBlock(nr)
                                    } label: {
                                        Text("\(nr)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                }
                section("Instrumente") { instrumentTable }
                if !song.dumps.isEmpty { section("SysEx-Dumps") { dumpTable } }
                section("Befehle") { commandTable }
                if !song.diagnostics.warnings.isEmpty || !song.diagnostics.notices.isEmpty {
                    section("Warnungen und Hinweise") { warnings }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Tabellen

    private var instrumentTable: some View {
        VStack(alignment: .leading, spacing: 2) {
            header(["#", "Kanal", "Preset", "Vol", "→MIDI", "Tr", "Hold", "NoteOff aus", "Name"],
                 widths: [26, 46, 50, 38, 46, 34, 42, 82, 200])
            ForEach(song.instruments, id: \.number) { i in
                HStack(spacing: 0) {
                    field("\(i.number)", 26)
                    field(i.isMIDI ? "\(i.midiChannel)" : "—", 46,
                         colour: i.isMIDI ? .primary : .secondary)
                    field(i.longPreset.map { $0 != 0 ? "\($0)" : "\(i.midiPreset)" }
                         ?? "\(i.midiPreset)", 50)
                    field("\(i.defaultVolume)", 38)
                    field(i.isMIDI ? "\(i.initialMIDIVolume)" : "—", 46,
                         colour: i.midiVolume != nil ? .primary : .secondary)
                    field("\(i.transpose)", 34)
                    field(i.hold.map(String.init) ?? "—", 42)
                    field(i.suppressNoteOff.map { $0 ? "ja" : "nein" } ?? "—", 82)
                    field(i.name.isEmpty ? "—" : i.name, 200)
                }
                .foregroundStyle(i.isMIDI ? Color.primary : Color.secondary)
            }
            Text("„→MIDI“ grau = aus svol gerechnet, weiß = undokumentiertes Feld der Datei")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
        }
    }

    private var dumpTable: some View {
        VStack(alignment: .leading, spacing: 2) {
            header(["#", "Name", "Bytes", "Nachrichten", "Hersteller", "Prüfung"],
                 widths: [26, 170, 66, 92, 78, 90])
            ForEach(song.dumps, id: \.index) { d in
                HStack(spacing: 0) {
                    field("\(d.index)", 26)
                    field(d.name.isEmpty ? "(ohne Namen)" : d.name, 170)
                    field("\(d.rawData.count)", 66)
                    field("\(d.messages.count)", 92)
                    field(d.manufacturer == 0x43 ? "Yamaha"
                         : d.manufacturer.map { String(format: "0x%02X", $0) } ?? "—", 78)
                    field(d.isComplete ? "F0…F7 ok" : "unvollständig", 90,
                         colour: d.isComplete ? .green : .red)
                }
            }
        }
    }

    private var commandTable: some View {
        VStack(alignment: .leading, spacing: 2) {
            header(["Befehl", "Anzahl", "Bedeutung (MIDI)"], widths: [56, 64, 320])
            ForEach(song.diagnostics.commandCounts.sorted { $0.key < $1.key }, id: \.key) { nr, count in
                let example = Command(number: nr, data: 0)
                HStack(spacing: 0) {
                    field(String(format: "%02X", nr), 56)
                    field("\(count)", 64)
                    field(meaning(nr), 320,
                         colour: CommandCatalog.midiEffect(nr) == .unknown ? .red : .primary)
                }
                .help(CommandCatalog.explanation(example))
                .onTapGesture { goTo(nr) }
            }
            Text("Klick springt zur ersten Fundstelle")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(song.diagnostics.warnings.enumerated()), id: \.offset) { _, w in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(w.description).textSelection(.enabled)
                }
                .font(.callout)
            }
            ForEach(Array(song.diagnostics.notices.enumerated()), id: \.offset) { _, h in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(h.message).textSelection(.enabled)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hilfen

    private func goTo(_ command: UInt8) {
        guard let location = song.diagnostics.commandLocations[command]?.first else { return }
        store.goToBlock(location.block)
        store.position.row = location.row
        store.position.page = location.page
    }

    private func meaning(_ nr: UInt8) -> String {
        switch CommandCatalog.midiEffect(nr) {
        case .controllerValue: return "Controller-Wert (Paar mit 05)"
        case .controllerNumber: return "Controller-Nummer wählen"
        case .velocity: return "Velocity"
        case .volumeController: return "Lautstärke CC7"
        case .pan: return "Pan CC10"
        case .modulationWheel: return "Modulationsrad CC1"
        case .setHold: return "Hold"
        case .ticksPerRow: return "Ticks pro Zeile"
        case .polyphonicAftertouch: return "Polyphoner Aftertouch"
        case .channelAftertouch: return "Kanal-Aftertouch"
        case .pitchBendUp: return "Pitchbend aufwärts"
        case .pitchBendDown: return "Pitchbend abwärts"
        case .setPitchBend: return "Pitchbend setzen"
        case .tempoOrSpecial: return "Tempo / Sonderfunktionen (FF = Note stoppen)"
        case .sendSysEx: return "SysEx-Dump senden"
        case .midiPreset: return "MIDI-Preset wechseln"
        case .repeatRows: return "Blockabschnitt wiederholen"
        case .jumpToNextSequence: return "Sprung zur nächsten Sequenz"
        case .repeatRow: return "Zeile wiederholen"
        case .playSequenceJump: return "Sprung in der Playsequenz"
        case .delayOrRetrigger: return "Note verzögern / retriggern"
        case .assignableController(let i):
            let number = i < song.cmd3xControllers.count ? song.cmd3xControllers[i].number : 0
            return "Freier Controller #\(i + 1) → CC\(number)"
        case .noEffectOnMIDI: return "ohne Wirkung bei MIDI"
        case .unknown: return "UNBEKANNT"
        }
    }

    @ViewBuilder
    private func section<Inhalt: View>(_ titel: String,
                                      @ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titel).font(.headline)
            inhalt()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(name).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func header(_ titel: [String], widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titel.enumerated()), id: \.offset) { i, t in
                Text(t).frame(width: widths[i], alignment: .leading)
            }
        }
        .font(.caption.bold()).foregroundStyle(.secondary)
    }

    private func field(_ message: String, _ width: CGFloat, colour: Color = .primary) -> some View {
        Text(message)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(colour)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }
}

/// Einfaches umbrechendes Layout für die Playsequenz-Knöpfe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x + g.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += g.width + spacing
            rowHeight = max(rowHeight, g.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x + g.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
            x += g.width + spacing
            rowHeight = max(rowHeight, g.height)
        }
    }
}
