import Foundation

/// Fehler beim Lesen einer MMD-Datei.
///
/// Die Spezifikation (MMD_FileFormat.doc, Abschnitt "rules you should obey")
/// verlangt: "Always use pointers, not absolute offsets" und "Check that a
/// pointer is nonzero before accessing anything it points to."
public enum MEDError: Error, CustomStringConvertible {
    case tooShort(needed: Int, available: Int)
    case noMMDSignature(gefunden: String)
    case pointerOutOfBounds(field: String, pointer: UInt32, fileSize: Int)
    case truncatedStructure(field: String, offset: Int)

    public var description: String {
        switch self {
        case .tooShort(let b, let v):
            return "Datei zu kurz: \(b) Bytes benötigt, \(v) vorhanden"
        case .noMMDSignature(let g):
            return "Keine MMD-Kennung: \(g)"
        case .pointerOutOfBounds(let f, let z, let d):
            return "Zeiger '\(f)' = 0x\(String(z, radix: 16)) liegt ausserhalb der Datei (\(d) Bytes)"
        case .truncatedStructure(let f, let o):
            return "Struktur '\(f)' bei Offset \(o) reicht über das Dateiende hinaus"
        }
    }
}

/// Liest Big-Endian-Werte (Amiga/68k) mit Grenzprüfung bei jedem Zugriff.
public struct ByteReader: Sendable {
    public let bytes: [UInt8]

    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public init(_ data: Data) { self.bytes = [UInt8](data) }

    public var count: Int { bytes.count }

    public func fits(_ offset: Int, _ length: Int) -> Bool {
        offset >= 0 && length >= 0 && offset &+ length <= bytes.count
    }

    public func u8(_ o: Int) throws -> UInt8 {
        guard fits(o, 1) else { throw MEDError.truncatedStructure(field: "u8", offset: o) }
        return bytes[o]
    }

    public func i8(_ o: Int) throws -> Int8 { Int8(bitPattern: try u8(o)) }

    public func u16(_ o: Int) throws -> UInt16 {
        guard fits(o, 2) else { throw MEDError.truncatedStructure(field: "u16", offset: o) }
        return UInt16(bytes[o]) << 8 | UInt16(bytes[o + 1])
    }

    public func i16(_ o: Int) throws -> Int16 { Int16(bitPattern: try u16(o)) }

    public func u32(_ o: Int) throws -> UInt32 {
        guard fits(o, 4) else { throw MEDError.truncatedStructure(field: "u32", offset: o) }
        return UInt32(bytes[o]) << 24 | UInt32(bytes[o + 1]) << 16
             | UInt32(bytes[o + 2]) << 8 | UInt32(bytes[o + 3])
    }

    /// Liest einen Amiga-Zeiger und prüft ihn gegen die Dateigröße.
    /// Gibt `nil` zurück, wenn der Zeiger null ist — laut Spezifikation ein
    /// gültiger Zustand, der "nicht vorhanden" bedeutet.
    public func pointer(_ o: Int, field: String) throws -> Int? {
        let z = try u32(o)
        if z == 0 { return nil }
        guard z < UInt32(bytes.count) else {
            throw MEDError.pointerOutOfBounds(field: field, pointer: z, fileSize: bytes.count)
        }
        return Int(z)
    }

    /// Nullterminierte Zeichenkette ab `o`, höchstens `maxLength` Bytes.
    public func string(_ o: Int, maxLength: Int) -> String {
        guard o > 0, o < bytes.count else { return "" }
        let limit = min(o + maxLength, bytes.count)
        var end = o
        while end < limit && bytes[end] != 0 { end += 1 }
        return Self.latin1(bytes[o..<end])
    }

    /// Zeichenkette fester Feldlänge, nullterminiert innerhalb des Feldes.
    public func fixedString(_ o: Int, length: Int) -> String {
        guard fits(o, length) else { return "" }
        var end = o
        while end < o + length && bytes[end] != 0 { end += 1 }
        return Self.latin1(bytes[o..<end])
    }

    /// Amiga-Texte sind ISO-8859-1. Jedes Byte ist genau ein Unicode-Skalar,
    /// deshalb ist die Umwandlung verlustfrei und kann nicht fehlschlagen —
    /// anders als eine UTF-8-Dekodierung, die an Umlauten scheitern würde.
    /// (Instrumentnamen der Testdateien enthalten "Fläche", "hände".)
    static func latin1(_ bytes: ArraySlice<UInt8>) -> String {
        String(String.UnicodeScalarView(bytes.map { UnicodeScalar($0) }))
    }
}
