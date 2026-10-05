import Foundation

/// Findet MED-Dateien unter einem Pfad.
///
/// **Nach Inhalt, nicht nach Endung.** Auf dem Amiga hatten die Dateien keine
/// Endung; der Autor hat sie später von Hand benannt — mal `.med`, mal `.MMD`,
/// mal `.mmd1`, und gepackte tragen zusätzlich `.pp`. Die Kennung am
/// Dateianfang ist das einzig Verlässliche: `MMD` plus eine Ziffer `0`–`3`.
///
/// Gelesen werden dafür vier Bytes je Datei, nicht der ganze Inhalt — ein
/// Archivordner kann tausende Dateien enthalten.
public enum MEDFileScan {

    /// Alle MED-Dateien unter `url`. Ist `url` eine Datei, enthält das
    /// Ergebnis sie selbst oder nichts.
    public static func medFiles(at url: URL) -> [URL] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        else { return [] }

        if !isFolder.boolValue { return isMEDFile(url) ? [url] : [] }

        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        var found: [URL] = []
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: Set(keys)))?.isRegularFile == true
            else { continue }
            if isMEDFile(file) { found.append(file) }
        }
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Prüft die Kennung, ohne die Datei ganz zu lesen.
    public static func isMEDFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let bytes = Array(head)
        return bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x44   // "MMD"
            && (0x30...0x33).contains(bytes[3])                           // '0'…'3'

    }
}
