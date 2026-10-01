import Foundation

/// Darstellung im OctaMED-Format.
///
/// Abgeleitet aus einem Bildschirmfoto von OctaMED SoundStudio V1.03c
/// (Amiga, deutsche Oberfläche) mit `O_Wie_Eine_Marionette.MMD`, Block 4.
/// Eine Zelle sieht dort so aus:
///
///     E-5 A0000
///     │   │└┴┴┴─ Befehl (2) und Datenbyte (2), je hexadezimal
///     │   └───── Instrumentnummer, eine Hexziffer
///     └───────── Notenname, drei Zeichen
public enum PatternRendering {

    /// Instrumentnummer als ein Zeichen, wie OctaMED sie anzeigt.
    ///
    /// Belegt ist nur 0–15 (Screenshot zeigt `A` für Instrument 10).
    /// Darüber wird Base-36 fortgesetzt (G = 16 …), was noch nicht gegen das
    /// Original geprüft ist — eine Datei mit mehr als 15 Instrumenten liegt
    /// vor (`unsere_hände_spielen.MMD`, 17), ein Screenshot dazu fehlt.
    public static func instrumentDigit(_ number: UInt8) -> String {
        let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let i = Int(number)
        return i < digits.count ? String(digits[i]) : "?"
    }

    public static func cell(_ z: Cell) -> String {
        "\(z.noteName) \(instrumentDigit(z.instrument))\(z.command.hex)"
    }

    /// Ein Block als Text, wie er in OctaMED auf dem Bildschirm steht.
    public static func block(_ block: Block, rows range: Range<Int>,
                             tracks spurBereich: Range<Int>? = nil,
                             page: Int = 0) -> String {
        let tracks = spurBereich ?? 0..<block.tracks
        var ausgabe: [String] = []
        for row in range where row < block.rows {
            var cells: [String] = []
            for track in tracks where track < block.tracks {
                let z = block.cell(row: row, track: track)
                if page == 0 {
                    cells.append(cell(z))
                } else {
                    let b = block.command(row: row, track: track, page: page)
                    cells.append("    \(b.hex)")
                }
            }
            ausgabe.append(String(format: "%03d   ", row) + cells.joined(separator: " "))
        }
        return ausgabe.joined(separator: "\n")
    }
}
