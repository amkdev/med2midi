import Foundation

/// Notennamen für MIDI-Notennummern.
public enum MIDINote {

    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Name einer MIDI-Note in der Zählung **Mitte C = C3**.
    ///
    /// Für die Oktavbenennung gibt es zwei verbreitete Zählungen, und beide
    /// sind gleich richtig: Mitte C (Note 60) heißt mal `C3`, mal `C4`. Hier
    /// gilt `C3`, weil die Werkzeuge des Autors es so halten — MIDI Monitor
    /// in seiner Einstellung und Bitwig von Haus aus. Wer die Anzeige mit der
    /// DAW vergleicht, soll denselben Namen lesen.
    ///
    /// Gegengeprüft an seiner Messung: Eine Note, die MIDI Monitor als `C-1`
    /// protokollierte, trug die Nummer 12 — und `12 / 12 − 2` ist −1.
    ///
    /// **Nicht zu verwechseln** mit `Cell.noteName`: Das ist OctaMEDs eigene
    /// Benennung im Pattern, die wieder eine Oktave höher zählt.
    public static func name(_ midiNote: UInt8) -> String {
        "\(names[Int(midiNote) % 12])\(Int(midiNote) / 12 - 2)"
    }
}
