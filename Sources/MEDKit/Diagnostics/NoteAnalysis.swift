import Foundation

/// Auffälligkeit im Notenverlauf — mögliche Fehler in den Songdaten selbst.
///
/// Der Autor: „es kann sich hier ein 0fff eingeschlichen haben, das da nicht
/// sein sollte … wenn 10 Instrumente klingen und irgendwo fehlt ein noteoff
/// oder ist zuviel, geht das auch mal akustisch unter."
///
/// Diese Prüfung läuft die **Songreihenfolge** durch, nicht die Blöcke
/// einzeln — Note-Offs stehen oft erst in Zeile 0 des folgenden Blocks.
public struct NoteFinding: Sendable, CustomStringConvertible {
    public enum Kind: Sendable {
        /// `0F FF` auf einer Spur, auf der nichts klingt.
        case noteOffWithoutNote
        /// `0F FF` mitten im Block, ohne dass dort etwas klingt.
        /// Am Blockanfang ist das übliche Vorsorge und wird nicht gemeldet.
        case noteOffMidBlock
        /// Am Songende klingt noch etwas.
        case openAtSongEnd(note: String, since: Int)
    }

    public let art: Kind
    public let location: SourceLocation
    public let sequencePosition: Int
    public let instrument: Int
    public let channel: UInt8

    public var description: String {
        let wo = "Sequenzposition \(sequencePosition), \(location)"
        switch art {
        case .noteOffWithoutNote:
            return "Note-Off ohne klingende Note — \(wo), Kanal \(channel)"
        case .noteOffMidBlock:
            return "Note-Off ohne klingende Note, mitten im Block — \(wo), Kanal \(channel)"
        case .openAtSongEnd(let note, let since):
            return "Am Songende klingt \(note) noch (seit Sequenzposition \(since)) "
                 + "— Instrument \(instrument), Kanal \(channel)"
        }
    }
}

public enum NoteAnalysis {

    /// Läuft die Songreihenfolge durch und meldet Auffälligkeiten.
    ///
    /// Bewusst **keine** vollständige Player-Simulation: Tempo, Verzögerungen
    /// und Sprungbefehle (`0B`, `1D`, `16`) bleiben aussen vor. Für die Frage
    /// „klingt hier etwas, das nicht klingen sollte" genügt der Notenzustand.
    public static func check(_ song: Song, songOrder: [Int]) -> [NoteFinding] {
        struct SoundingNote { let note: String; let instrument: UInt8; let since: Int }
        var sounding: [Int: SoundingNote] = [:]      // je Spur
        var activeInstrument: [Int: UInt8] = [:]
        var findings: [NoteFinding] = []

        func instrument(_ nr: UInt8) -> Instrument? {
            let i = Int(nr) - 1
            return i >= 0 && i < song.instruments.count ? song.instruments[i] : nil
        }

        for (pos, blockNr) in songOrder.enumerated() {
            guard blockNr < song.blocks.count else { continue }
            let block = song.blocks[blockNr]

            for row in 0..<block.rows {
                for track in 0..<block.tracks {
                    let z = block.cell(row: row, track: track)
                    if z.instrument != 0 { activeInstrument[track] = z.instrument }
                    let insNo = activeInstrument[track] ?? 0
                    guard let ins = instrument(insNo), ins.isMIDI else { continue }

                    let location = SourceLocation(block: blockNr, blockname: block.name,
                                         row: row, track: track, page: 0)

                    // Alle Befehlsseiten nach 0F FF absuchen.
                    var noteOff = false
                    for page in 0..<block.pageCount {
                        let b = block.command(row: row, track: track, page: page)
                        if b.number == 0x0F, b.data == 0xFF { noteOff = true }
                    }

                    if noteOff {
                        if sounding[track] == nil {
                            // Zeile 0 eines Blocks ist übliche Vorsorge: der Autor
                            // setzte Note-Offs bewusst an den Anfang des Folgeblocks,
                            // weil sie am Blockende die Note zu früh beendet hätten.
                            // Mitten im Block ist es dagegen auffällig.
                            findings.append(NoteFinding(
                                art: row == 0 ? .noteOffWithoutNote : .noteOffMidBlock,
                                location: location, sequencePosition: pos,
                                instrument: Int(insNo), channel: ins.midiChannel))
                        }
                        sounding[track] = nil
                    }

                    if z.note > 0 {
                        // Eine neue Note auf derselben Spur beendet die vorige —
                        // das ist Tracker-Normalfall und die dritte Quelle für
                        // Notenlängen neben Hold und 0F FF. Keine Auffälligkeit.
                        // Nur bei hold == 0 bleibt die neue Note danach offen.
                        sounding[track] = (ins.hold ?? 0) == 0
                            ? SoundingNote(note: z.noteName, instrument: insNo, since: pos)
                            : nil
                    }
                }
            }
        }

        for (track, k) in sounding.sorted(by: { $0.key < $1.key }) {
            guard let ins = instrument(k.instrument), ins.isMIDI else { continue }
            findings.append(NoteFinding(
                art: .openAtSongEnd(note: k.note, since: k.since),
                location: SourceLocation(block: songOrder.last ?? 0, blockname: "",
                                row: 0, track: track, page: 0),
                sequencePosition: songOrder.count - 1,
                instrument: Int(k.instrument), channel: ins.midiChannel))
        }
        return findings
    }

    /// Die Blockfolge in Songreihenfolge (Sections bzw. einzige Playsequenz).
    public static func songOrder(_ song: Song) -> [Int] {
        if song.version.hasSections, !song.sections.isEmpty {
            return song.sections.flatMap { abschnitt -> [Int] in
                guard abschnitt < song.playSequences.count else { return [] }
                return song.playSequences[abschnitt].blocks
            }
        }
        return song.playSequences.first?.blocks ?? []
    }
}
