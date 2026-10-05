import SwiftUI
import Observation
import MEDKit

/// Ein geladener Song samt Herkunft.
struct LoadedSong: Identifiable {
    let id = UUID()
    let url: URL
    let song: Song
}

/// Wo wir gerade im Song stehen.
struct Position: Equatable {
    var sequencePosition: Int = 0     // Index in der Playsequenz
    var block: Int = 0
    var row: Int = 0
    var page: Int = 0
}

@MainActor
@Observable
final class Store {
    var songs: [LoadedSong] = []
    var selection: LoadedSong.ID?
    var position = Position()
    var errorMessage: String?
    /// Nach Instrument einfärben (Projekt-Prompt, Punkt 2).
    var colourTracks = true

    // MARK: - Export

    /// Läuft gerade ein Export?
    var exporting = false
    /// Ergebnis des letzten Exports, für die Meldung.
    var exportReport: ExportReport?

    struct ExportReport: Identifiable {
        let id = UUID()
        let folder: URL
        let lines: [String]
        let failed: Bool
    }

    /// Zuletzt gewählter Zielordner, über Programmstarts hinweg.
    ///
    /// Als Lesezeichen abgelegt, nicht als Pfad: Ein Pfad bricht, sobald der
    /// Ordner umbenannt oder verschoben wird, das Lesezeichen folgt ihm.
    private static let bookmarkKey = "exportFolderBookmark"

    var exportFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale { remember(url) }
        return url
    }

    private func remember(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    /// Fragt nach dem Zielordner, wenn noch keiner gemerkt ist, und exportiert.
    func exportCurrent(askForFolder: Bool = false) {
        guard let loaded = current else { return }
        var ziel = askForFolder ? nil : exportFolder
        if ziel == nil {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Hierhin exportieren"
            panel.message = "Zielordner für den Export wählen. "
                          + "Je Song entsteht darin ein eigener Ordner."
            panel.directoryURL = exportFolder
            guard panel.runModal() == .OK, let gewaehlt = panel.url else { return }
            remember(gewaehlt)
            ziel = gewaehlt
        }
        guard let ordner = ziel else { return }
        export(loaded, to: ordner)
    }

    private func export(_ loaded: LoadedSong, to ordner: URL) {
        exporting = true
        let braucht = ordner.startAccessingSecurityScopedResource()
        defer { if braucht { ordner.stopAccessingSecurityScopedResource() } }
        do {
            let r = try Export.writeAll(song: loaded.song, to: ordner)
            var lines: [String] = []
            func groesse(_ u: URL) -> String {
                let n = (try? Data(contentsOf: u).count) ?? 0
                return n > 1_000_000 ? String(format: "%.1f MB", Double(n) / 1e6)
                                     : "\(n / 1000) kB"
            }
            lines.append("\(r.midi.url.lastPathComponent) — \(r.midi.trackCount) Spuren, "
                         + String(format: "%.1f s, ", r.midi.seconds) + groesse(r.midi.url))
            lines.append("\(r.relieved.url.lastPathComponent) — entzerrte Fassung, "
                         + groesse(r.relieved.url))
            if let sysEx = r.sysEx {
                lines.append("sysex/ — \(sysEx.dumps.count) Dumps, dumps.txt, parts.txt")
            } else {
                lines.append("Kein SysEx-Dump in dieser Datei.")
            }
            if !r.midi.warnings.isEmpty {
                lines.append("")
                lines.append("\(r.midi.warnings.count) Hinweise:")
                lines.append(contentsOf: r.midi.warnings.prefix(6).map { "• " + $0 })
                if r.midi.warnings.count > 6 {
                    lines.append("… \(r.midi.warnings.count - 6) weitere")
                }
            }
            exportReport = ExportReport(folder: r.folder, lines: lines, failed: false)
        } catch {
            exportReport = ExportReport(folder: ordner,
                                        lines: ["\(error)"], failed: true)
        }
        exporting = false
    }

    var current: LoadedSong? {
        songs.first { $0.id == selection } ?? songs.first
    }

    var currentBlock: Block? {
        guard let s = current, position.block < s.song.blocks.count else { return nil }
        return s.song.blocks[position.block]
    }

    // MARK: - Laden

    func load(_ urls: [URL]) {
        for url in urls {
            let braucht = url.startAccessingSecurityScopedResource()
            defer { if braucht { url.stopAccessingSecurityScopedResource() } }
            do {
                let song = try MEDLoader.load(file: url)
                songs.append(LoadedSong(url: url, song: song))
                if selection == nil {
                    selection = songs.last?.id
                    goToSongStart()
                }
            } catch {
                errorMessage = "\(url.lastPathComponent): \(error)"
            }
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "MED-/OctaMED-Songs öffnen"
        if panel.runModal() == .OK { load(panel.urls) }
    }

    func close(_ id: LoadedSong.ID) {
        songs.removeAll { $0.id == id }
        if selection == id { selection = songs.first?.id; goToSongStart() }
    }

    // MARK: - Navigation

    /// Die Blockfolge in Songreihenfolge. Bei MMD2/MMD3 über Sections,
    /// sonst die einzige Playsequenz.
    var songOrder: [Int] {
        guard let s = current?.song else { return [] }
        if s.version.hasSections, !s.sections.isEmpty {
            return s.sections.flatMap { abschnitt -> [Int] in
                guard abschnitt < s.playSequences.count else { return [] }
                return s.playSequences[abschnitt].blocks
            }
        }
        return s.playSequences.first?.blocks ?? []
    }

    func goToSongStart() {
        position = Position()
        if let first = songOrder.first { position.block = first }
    }

    func stepInSongOrder(_ richtung: Int) {
        let order = songOrder
        guard !order.isEmpty else { return }
        let neu = position.sequencePosition + richtung
        guard neu >= 0, neu < order.count else { return }
        position.sequencePosition = neu
        position.block = order[neu]
        position.row = 0
        position.page = 0
    }

    /// Springt an eine bestimmte Stelle der Songreihenfolge.
    ///
    /// Nicht über `goToBlock(_:)`: Derselbe Block kommt mehrfach vor, und das
    /// würde immer beim ersten Vorkommen landen. In `N_ich_will_neues` steht
    /// Block 7 an zwei Stellen.
    func goToSequencePosition(_ position: Int) {
        let order = songOrder
        guard position >= 0, position < order.count else { return }
        self.position.sequencePosition = position
        self.position.block = order[position]
        self.position.row = 0
        self.position.page = 0
    }

    func goToBlock(_ number: Int) {
        guard let s = current?.song, number >= 0, number < s.blocks.count else { return }
        position.block = number
        position.row = 0
        position.page = 0
        if let i = songOrder.firstIndex(of: number) { position.sequencePosition = i }
    }

    func moveRow(_ delta: Int) {
        guard let b = currentBlock, b.rows > 0 else { return }
        position.row = max(0, min(b.rows - 1, position.row + delta))
    }

    /// Bild auf/ab springt um vier Beats, nicht um eine feste Zeilenzahl.
    var pageStep: Int {
        max(1, (current?.song.rowsPerBeat ?? 4) * 4)
    }

    // MARK: - Zeitrechnung

    /// Dauer einer Zeile in Sekunden.
    ///
    /// Im BPM-Modus ist `deftempo` die BPM-Zahl und `rowsPerBeat` sagt, wie
    /// viele Zeilen auf einen Beat gehen. Sonst rechnet OctaMED wie
    /// ProTracker mit Ticks.
    ///
    /// **Am Original bestätigt** (2026-10-01): Für `O_Wie_Eine_Marionette.MMD`
    /// zeigt das Tempo-Fenster in OctaMED Tempo 066, TPL 005, LPB 015 — genau
    /// die hier gelesenen Werte. Die `+1`-Umrechnung von `flags2` („0 = 1
    /// line") stimmt also.
    ///
    /// **Noch nicht berücksichtigt:** Tempowechsel per Befehl `0F` und `09`.
    /// Das gehört in die Player-Simulation der Phase 2.
    var secondsPerRow: Double? {
        guard let s = current?.song, s.ticksPerRow > 0 else { return nil }
        guard let tick = Timing.tickDuration(song: s) else { return nil }
        return tick * Double(s.ticksPerRow)
    }

    /// Zeit ab Blockanfang bis zur aktuellen Zeile.
    var timeInBlock: String {
        guard let spz = secondsPerRow else { return "—" }
        let s = Double(position.row) * spz
        return String(format: "%d:%05.2f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    var barAndBeat: String {
        guard let s = current?.song, s.rowsPerBeat > 0 else { return "—" }
        let beat = position.row / s.rowsPerBeat
        let rest = position.row % s.rowsPerBeat
        return "\(beat + 1).\(rest + 1)"
    }
}
