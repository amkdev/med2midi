import SwiftUI
import MEDKit

struct SonginfoAnsicht: View {
    @Environment(Store.self) private var store
    let song: Song

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                gruppe("Allgemein") {
                    zeile("Format", song.version.name)
                    zeile("Songname", song.name.isEmpty ? "—" : song.name)
                    zeile("Datei", "\(song.dateiname)  ·  \(song.dateigröße) Bytes")
                    zeile("modlen", "\(song.modlen)"
                        + (Int(song.modlen) == song.dateigröße ? "  (= Dateigröße)" : "  ⚠︎ weicht ab"))
                    if song.weitereSongs > 0 {
                        zeile("Multi-Modul", "\(song.weitereSongs + 1) Songs in der Datei")
                    }
                }
                gruppe("Tempo") {
                    zeile("Tempo", song.bpmModus ? "\(song.standardTempo) BPM"
                                                 : "\(song.standardTempo) (Tracker-Tempo)")
                    zeile("Ticks pro Zeile", "\(song.ticksProZeile)")
                    zeile("Zeilen pro Beat", "\(song.zeilenProBeat)")
                    zeile("Transponierung", "\(song.songTransponierung)")
                    zeile("Mixing-Modus", song.mixingModus ? "ja" : "nein")
                }
                gruppe("Struktur") {
                    zeile("Blöcke", "\(song.blöcke.count)")
                    if song.version.hatSections {
                        zeile("Sections", song.sections.map(String.init).joined(separator: ", "))
                    }
                    ForEach(Array(song.playsequenzen.enumerated()), id: \.offset) { i, p in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name.isEmpty ? "Playsequenz \(i)" : "Playsequenz \(i): \(p.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            FlowLayout(spacing: 4) {
                                ForEach(Array(p.blöcke.enumerated()), id: \.offset) { j, nr in
                                    Button {
                                        store.position.sequenzPosition = j
                                        store.zuBlock(nr)
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
                gruppe("Instrumente") { instrumentTabelle }
                if !song.dumps.isEmpty { gruppe("SysEx-Dumps") { dumpTabelle } }
                gruppe("Befehle") { befehlsTabelle }
                if !song.diagnose.warnungen.isEmpty || !song.diagnose.hinweise.isEmpty {
                    gruppe("Warnungen und Hinweise") { warnungen }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Tabellen

    private var instrumentTabelle: some View {
        VStack(alignment: .leading, spacing: 2) {
            kopf(["#", "Kanal", "Preset", "Vol", "→MIDI", "Tr", "Hold", "NoteOff aus", "Name"],
                 breiten: [26, 46, 50, 38, 46, 34, 42, 82, 200])
            ForEach(song.instrumente, id: \.nummer) { i in
                HStack(spacing: 0) {
                    feld("\(i.nummer)", 26)
                    feld(i.istMIDI ? "\(i.midiKanal)" : "—", 46,
                         farbe: i.istMIDI ? .primary : .secondary)
                    feld(i.langesPreset.map { $0 != 0 ? "\($0)" : "\(i.midiPreset)" }
                         ?? "\(i.midiPreset)", 50)
                    feld("\(i.standardLautstärke)", 38)
                    feld(i.istMIDI ? "\(i.midiAnfangsLautstärke)" : "—", 46,
                         farbe: i.midiLautstärke != nil ? .primary : .secondary)
                    feld("\(i.transponierung)", 34)
                    feld(i.hold.map(String.init) ?? "—", 42)
                    feld(i.noteOffUnterdrücken.map { $0 ? "ja" : "nein" } ?? "—", 82)
                    feld(i.name.isEmpty ? "—" : i.name, 200)
                }
                .foregroundStyle(i.istMIDI ? Color.primary : Color.secondary)
            }
            Text("„→MIDI“ grau = aus svol gerechnet, weiß = undokumentiertes Feld der Datei")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
        }
    }

    private var dumpTabelle: some View {
        VStack(alignment: .leading, spacing: 2) {
            kopf(["#", "Name", "Bytes", "Nachrichten", "Hersteller", "Prüfung"],
                 breiten: [26, 170, 66, 92, 78, 90])
            ForEach(song.dumps, id: \.index) { d in
                HStack(spacing: 0) {
                    feld("\(d.index)", 26)
                    feld(d.name.isEmpty ? "(ohne Namen)" : d.name, 170)
                    feld("\(d.rohdaten.count)", 66)
                    feld("\(d.nachrichten.count)", 92)
                    feld(d.hersteller == 0x43 ? "Yamaha"
                         : d.hersteller.map { String(format: "0x%02X", $0) } ?? "—", 78)
                    feld(d.istVollständig ? "F0…F7 ok" : "unvollständig", 90,
                         farbe: d.istVollständig ? .green : .red)
                }
            }
        }
    }

    private var befehlsTabelle: some View {
        VStack(alignment: .leading, spacing: 2) {
            kopf(["Befehl", "Anzahl", "Bedeutung (MIDI)"], breiten: [56, 64, 320])
            ForEach(song.diagnose.befehlsStatistik.sorted { $0.key < $1.key }, id: \.key) { nr, anzahl in
                let beispiel = Befehl(nummer: nr, daten: 0)
                HStack(spacing: 0) {
                    feld(String(format: "%02X", nr), 56)
                    feld("\(anzahl)", 64)
                    feld(bedeutung(nr), 320,
                         farbe: Befehlskatalog.midiWirkung(nr) == .unbekannt ? .red : .primary)
                }
                .help(Befehlskatalog.erklärung(beispiel))
                .onTapGesture { springeZu(nr) }
            }
            Text("Klick springt zur ersten Fundstelle")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
        }
    }

    private var warnungen: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(song.diagnose.warnungen.enumerated()), id: \.offset) { _, w in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(w.description).textSelection(.enabled)
                }
                .font(.callout)
            }
            ForEach(Array(song.diagnose.hinweise.enumerated()), id: \.offset) { _, h in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(h.text).textSelection(.enabled)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hilfen

    private func springeZu(_ befehl: UInt8) {
        guard let ort = song.diagnose.befehlsFundstellen[befehl]?.first else { return }
        store.zuBlock(ort.block)
        store.position.zeile = ort.zeile
        store.position.seite = ort.seite
    }

    private func bedeutung(_ nr: UInt8) -> String {
        switch Befehlskatalog.midiWirkung(nr) {
        case .controllerWert: return "Controller-Wert (Paar mit 05)"
        case .controllerNummer: return "Controller-Nummer wählen"
        case .velocity: return "Velocity"
        case .lautstärkeController: return "Lautstärke CC7"
        case .pan: return "Pan CC10"
        case .modulationsrad: return "Modulationsrad CC1"
        case .holdSetzen: return "Hold"
        case .ticksProZeile: return "Ticks pro Zeile"
        case .polyphonerAftertouch: return "Polyphoner Aftertouch"
        case .kanalAftertouch: return "Kanal-Aftertouch"
        case .pitchbendAuf: return "Pitchbend aufwärts"
        case .pitchbendAb: return "Pitchbend abwärts"
        case .pitchbendSetzen: return "Pitchbend setzen"
        case .tempoOderSonderfall: return "Tempo / Sonderfunktionen (FF = Note stoppen)"
        case .sysexSenden: return "SysEx-Dump senden"
        case .midiPreset: return "MIDI-Preset wechseln"
        case .blockWiederholen: return "Blockabschnitt wiederholen"
        case .sprungNächsteSequenz: return "Sprung zur nächsten Sequenz"
        case .zeileWiederholen: return "Zeile wiederholen"
        case .playseqSprung: return "Sprung in der Playsequenz"
        case .verzögernOderRetrigger: return "Note verzögern / retriggern"
        case .freierController(let i):
            let nummer = i < song.cmd3xController.count ? song.cmd3xController[i].nummer : 0
            return "Freier Controller #\(i + 1) → CC\(nummer)"
        case .ohneWirkungBeiMIDI: return "ohne Wirkung bei MIDI"
        case .unbekannt: return "UNBEKANNT"
        }
    }

    @ViewBuilder
    private func gruppe<Inhalt: View>(_ titel: String,
                                      @ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titel).font(.headline)
            inhalt()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
    }

    private func zeile(_ name: String, _ wert: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(name).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(wert).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func kopf(_ titel: [String], breiten: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titel.enumerated()), id: \.offset) { i, t in
                Text(t).frame(width: breiten[i], alignment: .leading)
            }
        }
        .font(.caption.bold()).foregroundStyle(.secondary)
    }

    private func feld(_ text: String, _ breite: CGFloat, farbe: Color = .primary) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(farbe)
            .lineLimit(1)
            .frame(width: breite, alignment: .leading)
    }
}

/// Einfaches umbrechendes Layout für die Playsequenz-Knöpfe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, zeilenHöhe: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x + g.width > breite, x > 0 { x = 0; y += zeilenHöhe + spacing; zeilenHöhe = 0 }
            x += g.width + spacing
            zeilenHöhe = max(zeilenHöhe, g.height)
        }
        return CGSize(width: breite, height: y + zeilenHöhe)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, zeilenHöhe: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x + g.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += zeilenHöhe + spacing; zeilenHöhe = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
            x += g.width + spacing
            zeilenHöhe = max(zeilenHöhe, g.height)
        }
    }
}
