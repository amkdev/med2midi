import Foundation

/// Die Part-Einstellungen eines MU80 aus einem Speicherdump.
///
/// Der MU80 ist 32fach multitimbral, und jeder Part hat eine eigene
/// Klangwahl, Lautstärke, Panorama und Effektbelegung. Mehrere Parts dürfen
/// auf demselben MIDI-Kanal empfangen — dann klingen sie zusammen. Das sieht
/// man den MED-Daten nicht an, dort ist es ein Kanal.
///
/// **Belegt an den Dumps.** Sie folgen dem XG-Schema: Modell-ID `4C`,
/// Adresse `08 nn 00` für Part `nn`, danach die Parameter in fester
/// Reihenfolge. Die Deutung ist dreifach gegengeprüft:
///
/// - Die Empfangskanäle aller belegten Parts entsprechen den Kanälen der
///   MIDI-Instrumente der jeweiligen MED-Datei.
/// - `Note Shift` und `Pan` stehen bei den meisten Parts auf `0x40`, dem
///   Mittelwert — genau dort, wo Mittenwerte stehen müssen.
/// - `Part Mode` ist `0` bei allen melodischen Parts und zeigt bei den
///   Schlagzeugkanälen auf ein Drum-Setup.
public enum MultiPart {

    /// Ein Part, so wie er im Dump steht.
    public struct Part: Sendable {
        public let number: Int              // 1…32
        public let elementReserve: Int
        public let bankMSB: UInt8
        public let bankLSB: UInt8
        /// 0-basiert, wie im Dump. `programNumber + 1` ist die Anzeige.
        public let program: UInt8
        /// 1…16, oder `nil` wenn der Part nichts empfängt.
        public let channel: Int?
        public let partMode: UInt8
        /// Halbtöne, bereits um den Mittelwert `0x40` bereinigt.
        public let noteShift: Int
        public let volume: UInt8
        /// −64…+63, bereits bereinigt. 0 ist die Mitte.
        public let pan: Int
        public let reverbSend: UInt8
        public let chorusSend: UInt8
        public let variationSend: UInt8

        public var isDrumPart: Bool { partMode != 0 || bankMSB == 127 }

        /// Ob der Part unangetastet im Werkszustand steht.
        ///
        /// XG stellt jeden Part auf Bank 0/0, Programm 1, Lautstärke 100,
        /// Panorama Mitte, Hall 40, Chorus 0. Steht das alles noch so, hat der
        /// Autor diesen Part nie eingerichtet — der Klang auf diesem Kanal kam
        /// dann von einem anderen Gerät oder gar nicht.
        ///
        /// In `2_ENDZEIT_NEW` trifft das auf 24 der 32 Parts zu; der Song ist
        /// im Kern ein Wavestation-Song.
        public var isFactoryDefault: Bool {
            bankMSB == 0 && bankLSB == 0 && program == 0 && volume == 100
                && pan == 0 && reverbSend == 40 && chorusSend == 0
        }

        /// Name aus der GM-Liste, oder die Drum-Setup-Nummer.
        ///
        /// Die XG-Variante (`bankLSB`) ändert den Klang gegenüber GM, behält
        /// aber den Charakter. Für den genauen Namen gibt es die „Sound List"
        /// des MU80 — hier steht die Näherung samt Banknummern, mit denen sich
        /// dort nachschlagen lässt.
        public var voiceName: String {
            if isDrumPart { return "Drumkit \(Int(program) + 1)" }
            let i = Int(program)
            return i < MultiPart.generalMIDINames.count
                ? MultiPart.generalMIDINames[i] : "Programm \(i + 1)"
        }
    }

    /// Liest die Part-Einstellungen aus einem Dump.
    ///
    /// Enthält der Dump mehrere Sätze — manche Dateien speichern den Dump
    /// zweimal —, gilt der erste. Ein Part, der zweimal vorkommt, wird nicht
    /// überschrieben.
    public static func parts(in dump: SysExDump) -> [Part] {
        var result: [Part] = []
        var seen = Set<Int>()

        for message in dump.messages {
            let m = Array(message)
            // F0 43 0n 4C bh bl ah am al <daten> cs F7
            guard m.count > 12, m[1] == 0x43, m[3] == 0x4C,
                  m[6] == 0x08, m[8] == 0x00 else { continue }
            let number = Int(m[7])
            guard !seen.contains(number) else { continue }
            let d = Array(m[9..<(m.count - 2)])
            guard d.count > 20 else { continue }
            seen.insert(number)

            let channel = d[4] < 16 ? Int(d[4]) + 1 : nil
            result.append(Part(number: number + 1,
                               elementReserve: Int(d[0]),
                               bankMSB: d[1], bankLSB: d[2], program: d[3],
                               channel: channel,
                               partMode: d[7],
                               noteShift: Int(d[8]) - 64,
                               volume: d[11],
                               pan: Int(d[14]) - 64,
                               reverbSend: d[19],
                               chorusSend: d[18],
                               variationSend: d[20]))
        }
        return result.sorted { $0.number < $1.number }
    }

    /// Die 128 Namen der General-MIDI-Klangliste, auf der XG aufbaut.
    public static let generalMIDINames = [
        "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano",
        "Honky-tonk Piano", "Electric Piano 1", "Electric Piano 2", "Harpsichord",
        "Clavi", "Celesta", "Glockenspiel", "Music Box", "Vibraphone", "Marimba",
        "Xylophone", "Tubular Bells", "Dulcimer", "Drawbar Organ", "Percussive Organ",
        "Rock Organ", "Church Organ", "Reed Organ", "Accordion", "Harmonica",
        "Tango Accordion", "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)",
        "Electric Guitar (jazz)", "Electric Guitar (clean)", "Electric Guitar (muted)",
        "Overdriven Guitar", "Distortion Guitar", "Guitar harmonics", "Acoustic Bass",
        "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass", "Slap Bass 1",
        "Slap Bass 2", "Synth Bass 1", "Synth Bass 2", "Violin", "Viola", "Cello",
        "Contrabass", "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp",
        "Timpani", "String Ensemble 1", "String Ensemble 2", "SynthStrings 1",
        "SynthStrings 2", "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
        "Trumpet", "Trombone", "Tuba", "Muted Trumpet", "French Horn", "Brass Section",
        "SynthBrass 1", "SynthBrass 2", "Soprano Sax", "Alto Sax", "Tenor Sax",
        "Baritone Sax", "Oboe", "English Horn", "Bassoon", "Clarinet", "Piccolo",
        "Flute", "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle",
        "Ocarina", "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)",
        "Lead 4 (chiff)", "Lead 5 (charang)", "Lead 6 (voice)", "Lead 7 (fifths)",
        "Lead 8 (bass+lead)", "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)",
        "Pad 4 (choir)", "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)",
        "Pad 8 (sweep)", "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)",
        "FX 4 (atmosphere)", "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)",
        "FX 8 (sci-fi)", "Sitar", "Banjo", "Shamisen", "Koto", "Kalimba", "Bag pipe",
        "Fiddle", "Shanai", "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
        "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
        "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
        "Telephone Ring", "Helicopter", "Applause", "Gunshot",
    ]
}
