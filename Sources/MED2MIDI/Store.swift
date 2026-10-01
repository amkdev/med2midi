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
        guard let s = current?.song else { return nil }
        if s.bpmMode {
            let bpm = Double(s.defaultTempo)
            guard bpm > 0 else { return nil }
            return 60.0 / (bpm * Double(s.rowsPerBeat))
        }
        // Nicht-BPM-Modus: Ticks pro Zeile bei 50 Hz Amiga-Raster.
        let ticks = Double(s.ticksPerRow)
        let tempo = Double(s.defaultTempo)
        guard ticks > 0, tempo > 0 else { return nil }
        return ticks * (2.5 / tempo)
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
