import SwiftUI
import Observation
import MEDKit

/// Ein geladener Song samt Herkunft.
struct GeladenerSong: Identifiable {
    let id = UUID()
    let url: URL
    let song: Song
}

/// Wo wir gerade im Song stehen.
struct Position: Equatable {
    var sequenzPosition: Int = 0     // Index in der Playsequenz
    var block: Int = 0
    var zeile: Int = 0
    var seite: Int = 0
}

@MainActor
@Observable
final class Store {
    var songs: [GeladenerSong] = []
    var auswahl: GeladenerSong.ID?
    var position = Position()
    var fehler: String?
    /// Nach Instrument einfärben (Projekt-Prompt, Punkt 2).
    var spurenEinfärben = true

    var aktiv: GeladenerSong? {
        songs.first { $0.id == auswahl } ?? songs.first
    }

    var aktiverBlock: Block? {
        guard let s = aktiv, position.block < s.song.blöcke.count else { return nil }
        return s.song.blöcke[position.block]
    }

    // MARK: - Laden

    func lade(_ urls: [URL]) {
        for url in urls {
            let braucht = url.startAccessingSecurityScopedResource()
            defer { if braucht { url.stopAccessingSecurityScopedResource() } }
            do {
                let song = try MEDLoader.lade(datei: url)
                songs.append(GeladenerSong(url: url, song: song))
                if auswahl == nil {
                    auswahl = songs.last?.id
                    springeAnSongAnfang()
                }
            } catch {
                fehler = "\(url.lastPathComponent): \(error)"
            }
        }
    }

    func öffnenDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "MED-/OctaMED-Songs öffnen"
        if panel.runModal() == .OK { lade(panel.urls) }
    }

    func schließe(_ id: GeladenerSong.ID) {
        songs.removeAll { $0.id == id }
        if auswahl == id { auswahl = songs.first?.id; springeAnSongAnfang() }
    }

    // MARK: - Navigation

    /// Die Blockfolge in Songreihenfolge. Bei MMD2/MMD3 über Sections,
    /// sonst die einzige Playsequenz.
    var songFolge: [Int] {
        guard let s = aktiv?.song else { return [] }
        if s.version.hatSections, !s.sections.isEmpty {
            return s.sections.flatMap { abschnitt -> [Int] in
                guard abschnitt < s.playsequenzen.count else { return [] }
                return s.playsequenzen[abschnitt].blöcke
            }
        }
        return s.playsequenzen.first?.blöcke ?? []
    }

    func springeAnSongAnfang() {
        position = Position()
        if let erster = songFolge.first { position.block = erster }
    }

    func weiterInSongreihenfolge(_ richtung: Int) {
        let folge = songFolge
        guard !folge.isEmpty else { return }
        let neu = position.sequenzPosition + richtung
        guard neu >= 0, neu < folge.count else { return }
        position.sequenzPosition = neu
        position.block = folge[neu]
        position.zeile = 0
        position.seite = 0
    }

    func zuBlock(_ nummer: Int) {
        guard let s = aktiv?.song, nummer >= 0, nummer < s.blöcke.count else { return }
        position.block = nummer
        position.zeile = 0
        position.seite = 0
        if let i = songFolge.firstIndex(of: nummer) { position.sequenzPosition = i }
    }

    func zeileVerschieben(_ delta: Int) {
        guard let b = aktiverBlock, b.zeilen > 0 else { return }
        position.zeile = max(0, min(b.zeilen - 1, position.zeile + delta))
    }

    // MARK: - Zeitrechnung

    /// Dauer einer Zeile in Sekunden.
    ///
    /// Im BPM-Modus ist `deftempo` die BPM-Zahl und `zeilenProBeat` sagt, wie
    /// viele Zeilen auf einen Beat gehen. Sonst rechnet OctaMED wie
    /// ProTracker mit Ticks.
    ///
    /// **Ungeprüft**: gegen den Emulator noch nicht abgeglichen. Tempowechsel
    /// per Befehl 0F und 09 sind hier ebenfalls noch nicht berücksichtigt —
    /// das gehört in die Player-Simulation der Phase 2.
    var sekundenProZeile: Double? {
        guard let s = aktiv?.song else { return nil }
        if s.bpmModus {
            let bpm = Double(s.standardTempo)
            guard bpm > 0 else { return nil }
            return 60.0 / (bpm * Double(s.zeilenProBeat))
        }
        // Nicht-BPM-Modus: Ticks pro Zeile bei 50 Hz Amiga-Raster.
        let ticks = Double(s.ticksProZeile)
        let tempo = Double(s.standardTempo)
        guard ticks > 0, tempo > 0 else { return nil }
        return ticks * (2.5 / tempo)
    }

    /// Zeit ab Blockanfang bis zur aktuellen Zeile.
    var zeitImBlock: String {
        guard let spz = sekundenProZeile else { return "—" }
        let s = Double(position.zeile) * spz
        return String(format: "%d:%05.2f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    var taktUndBeat: String {
        guard let s = aktiv?.song, s.zeilenProBeat > 0 else { return "—" }
        let beat = position.zeile / s.zeilenProBeat
        let rest = position.zeile % s.zeilenProBeat
        return "\(beat + 1).\(rest + 1)"
    }
}
