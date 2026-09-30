import Foundation

/// Formatversion aus der Dateikennung.
///
/// Quelle: MMD_FileFormat.doc Rev. 6, Abschnitt "id":
/// MMD0 = 0x4D4D4430 … MMD3 = 0x4D4D4433.
/// "Note that MMD2 and MMD3 file formats are identical."
public enum MMDVersion: UInt8, Sendable, CaseIterable {
    case mmd0 = 0, mmd1 = 1, mmd2 = 2, mmd3 = 3

    public init?(kennung: UInt32) {
        guard kennung >> 8 == 0x4D4D44 else { return nil }   // "MMD"
        let ziffer = UInt8(kennung & 0xFF)
        guard ziffer >= 0x30, ziffer <= 0x33 else { return nil }
        self.init(rawValue: ziffer - 0x30)
    }

    public var name: String { "MMD\(rawValue)" }

    /// MMD0 hat 3-Byte-Noten mit 4-Bit-Befehl, ab MMD1 sind es 4-Byte-Noten
    /// mit vollem Befehlsbyte. (Spezifikation, "The block format".)
    public var notenBytes: Int { self == .mmd0 ? 3 : 4 }

    /// MMD0: `struct MMD0Block { UBYTE numtracks, lines; }` = 2 Bytes.
    /// Ab MMD1: `struct MMD1Block { UWORD numtracks, lines; BlockInfo *info; }` = 8 Bytes.
    public var blockKopfBytes: Int { self == .mmd0 ? 2 : 8 }

    /// Ab MMD2 gilt die MMD2song-Struktur mit Sections und Playseq-Tabelle.
    public var hatSections: Bool { self == .mmd2 || self == .mmd3 }
}
