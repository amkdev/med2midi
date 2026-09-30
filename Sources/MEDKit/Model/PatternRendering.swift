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
public enum PatternDarstellung {

    /// Instrumentnummer als ein Zeichen, wie OctaMED sie anzeigt.
    ///
    /// Belegt ist nur 0–15 (Screenshot zeigt `A` für Instrument 10).
    /// Darüber wird Base-36 fortgesetzt (G = 16 …), was noch nicht gegen das
    /// Original geprüft ist — eine Datei mit mehr als 15 Instrumenten liegt
    /// vor (`unsere_hände_spielen.MMD`, 17), ein Screenshot dazu fehlt.
    public static func instrumentZeichen(_ nummer: UInt8) -> String {
        let ziffern = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let i = Int(nummer)
        return i < ziffern.count ? String(ziffern[i]) : "?"
    }

    public static func zelle(_ z: Zelle) -> String {
        "\(z.notenName) \(instrumentZeichen(z.instrument))\(z.befehl.hex)"
    }

    /// Ein Block als Text, wie er in OctaMED auf dem Bildschirm steht.
    public static func block(_ block: Block, zeilen bereich: Range<Int>,
                             spuren spurBereich: Range<Int>? = nil,
                             seite: Int = 0) -> String {
        let spuren = spurBereich ?? 0..<block.spuren
        var ausgabe: [String] = []
        for zeile in bereich where zeile < block.zeilen {
            var zellen: [String] = []
            for spur in spuren where spur < block.spuren {
                let z = block.zelle(zeile: zeile, spur: spur)
                if seite == 0 {
                    zellen.append(zelle(z))
                } else {
                    let b = block.befehl(zeile: zeile, spur: spur, seite: seite)
                    zellen.append("    \(b.hex)")
                }
            }
            ausgabe.append(String(format: "%03d   ", zeile) + zellen.joined(separator: " "))
        }
        return ausgabe.joined(separator: "\n")
    }
}
