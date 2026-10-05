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
    /// Auswahl in der Songliste. Mehrfachauswahl, damit sich mehrere auf
    /// einmal entfernen lassen; angezeigt wird der erste in Listenreihenfolge.
    var selection: Set<LoadedSong.ID> = []
    var position = Position()
    var errorMessage: String?
    /// Nach Instrument einfärben (Projekt-Prompt, Punkt 2).
    var colourTracks = true

    // MARK: - Export

    /// Läuft gerade ein Export?
    var exporting = false
    /// Ergebnis des letzten Exports, für die Meldung.
    var exportReport: ExportReport?
    /// Fortschritt beim Stapelexport.
    var exportProgress: (done: Int, total: Int)?

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

    /// Die Songs, die ein Stapelexport erfassen würde: die Auswahl, sobald
    /// mehr als einer markiert ist, sonst alle geladenen.
    var batchSongs: [LoadedSong] {
        selection.count > 1 ? songs.filter { selection.contains($0.id) } : songs
    }

    /// Exportiert mehrere Songs in denselben Zielordner.
    ///
    /// Die Arbeit läuft neben dem Hauptthread: Bei sieben Dateien dauert sie
    /// mehrere Sekunden, und solange soll sich das Fenster weiter bedienen
    /// lassen.
    func exportAll(askForFolder: Bool = false) {
        let liste = batchSongs
        guard !liste.isEmpty else { return }
        guard let ordner = chooseFolder(ask: askForFolder) else { return }
        exporting = true
        exportProgress = (0, liste.count)

        Task {
            var zeilen: [String] = []
            var fehler = 0
            for (i, loaded) in liste.enumerated() {
                let song = loaded.song
                let ergebnis = await Task.detached(priority: .userInitiated) {
                    Result { try Export.writeAll(song: song, to: ordner) }
                }.value
                switch ergebnis {
                case .success(let r):
                    var zeile = "\(r.folder.lastPathComponent)/  "
                        + "\(r.midi.trackCount) Spuren, "
                        + String(format: "%.1f s", r.midi.seconds)
                    if let sysEx = r.sysEx { zeile += ", \(sysEx.dumps.count) Dumps" }
                    if !r.midi.warnings.isEmpty {
                        zeile += "  (\(r.midi.warnings.count) Hinweise)"
                    }
                    zeilen.append(zeile)
                case .failure(let error):
                    fehler += 1
                    zeilen.append("FEHLER  \(loaded.url.lastPathComponent): \(error)")
                }
                exportProgress = (i + 1, liste.count)
            }
            zeilen.append("")
            zeilen.append(fehler == 0
                          ? "\(liste.count) Songs exportiert."
                          : "\(liste.count - fehler) von \(liste.count) exportiert, \(fehler) fehlgeschlagen.")
            exportReport = ExportReport(folder: ordner, lines: zeilen, failed: fehler > 0)
            exportProgress = nil
            exporting = false
        }
    }

    /// Zielordner, gemerkt oder frisch gewählt.
    private func chooseFolder(ask: Bool) -> URL? {
        if !ask, let gemerkt = exportFolder { return gemerkt }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Hierhin exportieren"
        panel.message = "Zielordner für den Export wählen. "
                      + "Je Song entsteht darin ein eigener Ordner."
        panel.directoryURL = exportFolder
        guard panel.runModal() == .OK, let gewaehlt = panel.url else { return nil }
        remember(gewaehlt)
        return gewaehlt
    }

    /// Fragt nach dem Zielordner, wenn noch keiner gemerkt ist, und exportiert.
    func exportCurrent(askForFolder: Bool = false) {
        guard let loaded = current else { return }
        guard let ordner = chooseFolder(ask: askForFolder) else { return }
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
        songs.first { selection.contains($0.id) } ?? songs.first
    }

    var currentBlock: Block? {
        guard let s = current, position.block < s.song.blocks.count else { return nil }
        return s.song.blocks[position.block]
    }

    // MARK: - Laden

    /// Läuft gerade eine Ordnersuche?
    var scanning = false

    /// Nimmt entgegen, was aus dem Öffnen-Dialog oder vom Ablegen kommt:
    /// Dateien **und** Ordner, in beliebiger Mischung.
    ///
    /// Die Suche läuft neben dem Hauptthread. Ein Archivordner kann tausende
    /// Dateien enthalten, und von jeder werden vier Bytes gelesen — das
    /// soll das Fenster nicht anhalten.
    func accept(_ urls: [URL]) {
        let roots = urls.filter(\.isFileURL)
        guard !roots.isEmpty else { return }
        scanning = true
        Task {
            let gefunden = await Task.detached(priority: .userInitiated) {
                roots.flatMap { MEDFileScan.medFiles(at: $0) }
            }.value
            scanning = false
            guard !gefunden.isEmpty else {
                errorMessage = roots.count == 1 && roots[0].hasDirectoryPath
                    ? "In „\(roots[0].lastPathComponent)“ liegt keine MED-Datei. "
                    + "Gesucht wird nach der Kennung am Dateianfang, nicht nach der Endung."
                    : "Keine MED-Datei dabei."
                return
            }
            load(gefunden)
        }
    }

    func load(_ urls: [URL]) {
        var fehler: [String] = []
        for url in urls {
            let braucht = url.startAccessingSecurityScopedResource()
            defer { if braucht { url.stopAccessingSecurityScopedResource() } }
            do {
                let song = try MEDLoader.load(file: url)
                songs.append(LoadedSong(url: url, song: song))
                if selection.isEmpty {
                    selection = [songs.last!.id]
                    goToSongStart()
                }
            } catch {
                fehler.append("\(url.lastPathComponent): \(error)")
            }
        }
        if !fehler.isEmpty {
            // Alle auf einmal, nicht nur den letzten: Beim Laden eines ganzen
            // Ordners ginge sonst jede Meldung bis auf eine verloren.
            errorMessage = fehler.count == 1
                ? fehler[0]
                : "\(fehler.count) Dateien konnten nicht gelesen werden:\n\n"
                  + fehler.prefix(10).joined(separator: "\n")
                  + (fehler.count > 10 ? "\n… \(fehler.count - 10) weitere" : "")
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "MED-/OctaMED-Songs öffnen. Ordner werden durchsucht."
        guard panel.runModal() == .OK else { return }
        accept(panel.urls)
    }


    /// Entfernt Songs aus der Liste. Die Dateien bleiben unangetastet —
    /// MEDKit hat ohnehin keinen Schreibpfad.
    func close(_ ids: Set<LoadedSong.ID>) {
        guard !ids.isEmpty else { return }
        // Was nach dem Entfernen angezeigt wird: der nächste in der Liste,
        // sonst der vorige. Nichts auszuwählen wäre unnötig unfreundlich.
        let nachfolger = nextAfterRemoving(ids)
        songs.removeAll { ids.contains($0.id) }
        selection = nachfolger.map { [$0] } ?? Set(songs.first.map { [$0.id] } ?? [])
        goToSongStart()
    }

    func close(_ id: LoadedSong.ID) { close([id]) }

    /// Entfernt die Auswahl.
    func closeSelected() { close(selection) }

    func closeAll() {
        songs.removeAll()
        selection = []
        goToSongStart()
    }

    private func nextAfterRemoving(_ ids: Set<LoadedSong.ID>) -> LoadedSong.ID? {
        guard let letzter = songs.lastIndex(where: { ids.contains($0.id) }) else { return nil }
        if let danach = songs[(letzter + 1)...].first { return danach.id }
        guard let erster = songs.firstIndex(where: { ids.contains($0.id) }), erster > 0
        else { return nil }
        return songs[erster - 1].id
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
