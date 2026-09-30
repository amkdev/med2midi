import Foundation

/// Auffälligkeit im Notenverlauf — mögliche Fehler in den Songdaten selbst.
///
/// Der Autor: „es kann sich hier ein 0fff eingeschlichen haben, das da nicht
/// sein sollte … wenn 10 Instrumente klingen und irgendwo fehlt ein noteoff
/// oder ist zuviel, geht das auch mal akustisch unter."
///
/// Diese Prüfung läuft die **Songreihenfolge** durch, nicht die Blöcke
/// einzeln — Note-Offs stehen oft erst in Zeile 0 des folgenden Blocks.
public struct Notenbefund: Sendable, CustomStringConvertible {
    public enum Art: Sendable {
        /// `0F FF` auf einer Spur, auf der nichts klingt.
        case noteOffOhneNote
        /// `0F FF` mitten im Block, ohne dass dort etwas klingt.
        /// Am Blockanfang ist das übliche Vorsorge und wird nicht gemeldet.
        case noteOffMittenImBlock
        /// Am Songende klingt noch etwas.
        case amSongendeOffen(note: String, seit: Int)
    }

    public let art: Art
    public let ort: Fundstelle
    public let sequenzPosition: Int
    public let instrument: Int
    public let kanal: UInt8

    public var description: String {
        let wo = "Sequenzposition \(sequenzPosition), \(ort)"
        switch art {
        case .noteOffOhneNote:
            return "Note-Off ohne klingende Note — \(wo), Kanal \(kanal)"
        case .noteOffMittenImBlock:
            return "Note-Off ohne klingende Note, mitten im Block — \(wo), Kanal \(kanal)"
        case .amSongendeOffen(let note, let seit):
            return "Am Songende klingt \(note) noch (seit Sequenzposition \(seit)) "
                 + "— Instrument \(instrument), Kanal \(kanal)"
        }
    }
}

public enum Notenanalyse {

    /// Läuft die Songreihenfolge durch und meldet Auffälligkeiten.
    ///
    /// Bewusst **keine** vollständige Player-Simulation: Tempo, Verzögerungen
    /// und Sprungbefehle (`0B`, `1D`, `16`) bleiben aussen vor. Für die Frage
    /// „klingt hier etwas, das nicht klingen sollte" genügt der Notenzustand.
    public static func prüfe(_ song: Song, songFolge: [Int]) -> [Notenbefund] {
        struct Klingend { let note: String; let instrument: UInt8; let seit: Int }
        var offen: [Int: Klingend] = [:]      // je Spur
        var aktivesInstrument: [Int: UInt8] = [:]
        var befunde: [Notenbefund] = []

        func instrument(_ nr: UInt8) -> Instrument? {
            let i = Int(nr) - 1
            return i >= 0 && i < song.instrumente.count ? song.instrumente[i] : nil
        }

        for (pos, blockNr) in songFolge.enumerated() {
            guard blockNr < song.blöcke.count else { continue }
            let block = song.blöcke[blockNr]

            for zeile in 0..<block.zeilen {
                for spur in 0..<block.spuren {
                    let z = block.zelle(zeile: zeile, spur: spur)
                    if z.instrument != 0 { aktivesInstrument[spur] = z.instrument }
                    let insNr = aktivesInstrument[spur] ?? 0
                    guard let ins = instrument(insNr), ins.istMIDI else { continue }

                    let ort = Fundstelle(block: blockNr, blockname: block.name,
                                         zeile: zeile, spur: spur, seite: 0)

                    // Alle Befehlsseiten nach 0F FF absuchen.
                    var noteOff = false
                    for seite in 0..<block.seitenAnzahl {
                        let b = block.befehl(zeile: zeile, spur: spur, seite: seite)
                        if b.nummer == 0x0F, b.daten == 0xFF { noteOff = true }
                    }

                    if noteOff {
                        if offen[spur] == nil {
                            // Zeile 0 eines Blocks ist übliche Vorsorge: der Autor
                            // setzte Note-Offs bewusst an den Anfang des Folgeblocks,
                            // weil sie am Blockende die Note zu früh beendet hätten.
                            // Mitten im Block ist es dagegen auffällig.
                            befunde.append(Notenbefund(
                                art: zeile == 0 ? .noteOffOhneNote : .noteOffMittenImBlock,
                                ort: ort, sequenzPosition: pos,
                                instrument: Int(insNr), kanal: ins.midiKanal))
                        }
                        offen[spur] = nil
                    }

                    if z.note > 0 {
                        // Eine neue Note auf derselben Spur beendet die vorige —
                        // das ist Tracker-Normalfall und die dritte Quelle für
                        // Notenlängen neben Hold und 0F FF. Keine Auffälligkeit.
                        // Nur bei hold == 0 bleibt die neue Note danach offen.
                        offen[spur] = (ins.hold ?? 0) == 0
                            ? Klingend(note: z.notenName, instrument: insNr, seit: pos)
                            : nil
                    }
                }
            }
        }

        for (spur, k) in offen.sorted(by: { $0.key < $1.key }) {
            guard let ins = instrument(k.instrument), ins.istMIDI else { continue }
            befunde.append(Notenbefund(
                art: .amSongendeOffen(note: k.note, seit: k.seit),
                ort: Fundstelle(block: songFolge.last ?? 0, blockname: "",
                                zeile: 0, spur: spur, seite: 0),
                sequenzPosition: songFolge.count - 1,
                instrument: Int(k.instrument), kanal: ins.midiKanal))
        }
        return befunde
    }

    /// Die Blockfolge in Songreihenfolge (Sections bzw. einzige Playsequenz).
    public static func songFolge(_ song: Song) -> [Int] {
        if song.version.hatSections, !song.sections.isEmpty {
            return song.sections.flatMap { abschnitt -> [Int] in
                guard abschnitt < song.playsequenzen.count else { return [] }
                return song.playsequenzen[abschnitt].blöcke
            }
        }
        return song.playsequenzen.first?.blöcke ?? []
    }
}
