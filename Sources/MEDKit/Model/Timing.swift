import Foundation

/// Zeitrechnung nach der Original-Playroutine.
///
/// Quelle: `MED_PlayRoutine.i`, `_SetTempo`. OctaMED stellt dort den
/// CIA-Timer ein; dessen Periode bestimmt die Tickrate, und daraus folgt
/// alles andere.
///
/// ```asm
/// .ST_bpm:                   ; BPM-Modus
///     MOVE.B  msng_flags2(A0),D1
///     AND.W   #$1F,D1
///     ADDQ.B  #1,D1          ; LPB = (flags2 & 0x1F) + 1
///     MULU    D1,D0          ; Tempo × LPB
///     MOVE.L  bpmdiv,D1
///     DIVU    D0,D1          ; Periode = bpmdiv / (Tempo × LPB)
///
/// .calctempo:                ; SPD-Modus, Tempo > 10
///     MOVE.L  timerdiv,D1    ; timerdiv = 470000
///     DIVU    D0,D1          ; Periode = timerdiv / Tempo
/// ```
public enum Timing {

    /// Taktfrequenz des CIA-Timers auf einem PAL-Amiga.
    ///
    /// Die Playroutine rechnet mit `timerdiv = 470000`; ein Kommentar bei der
    /// Initialisierung nennt alternativ 474326 für 715 909 Hz (NTSC).
    public static let ciaClockPAL = 709_379.0
    static let timerDiv = 470_000.0
    /// `bpmdiv: DC.L 3546895/2` — der halbe PAL-Farbträgertakt.
    static let bpmDiv = Double(3_546_895 / 2)

    /// Dauer eines Ticks in Sekunden.
    ///
    /// **BPM-Modus.** `_SetTempo` setzt die CIA-Periode auf
    /// `bpmdiv / (Tempo × LPB)` mit `bpmdiv = 3546895/2 = 1773447`. Der
    /// Interrupt-Handler teilt zusätzlich durch vier (`bpmcounter`), der Timer
    /// feuert dort also viermal je Spieltick:
    ///
    /// ```asm
    /// SUBQ.B  #1,bpmcounter
    /// BLE.S   .plr_bpmcnt0
    /// BRA.W   .plr_exit
    /// .plr_bpmcnt0:
    /// MOVE.B  #4,bpmcounter
    /// ```
    ///
    /// Mit dem PAL-E-Takt 709 379 Hz ergibt das
    ///
    ///     Tickrate = 709379 × (Tempo × LPB) / (1773447 × 4) = (Tempo × LPB) / 10 Hz
    ///
    /// Eine Zeile dauert `TPL` Ticks (`mmd_counter` zählt bis `tempo2`), also
    /// `TPL × 10 / (Tempo × LPB)`.
    ///
    /// **Achtung:** Die verbreitete Formel `60 / (BPM × LPB)` stimmt nur bei
    /// `TPL = 6`. Bei `O_Wie_Eine_Marionette.MMD` (TPL 5) liegt sie um 20 %
    /// daneben — 60,6 statt 50,5 ms je Zeile.
    ///
    /// **SPD-Modus.** Periode `timerdiv / Tempo` mit `timerdiv = 470000`, ohne
    /// den Vierer-Teiler. Tempo 33 ergibt 49,81 Ticks je Sekunde — die
    /// klassischen 50 Hz des Amiga.
    public static func tickDuration(song: Song) -> Double? {
        guard song.ticksPerRow > 0 else { return nil }
        if song.bpmMode {
            let product = Double(song.defaultTempo) * Double(song.rowsPerBeat)
            guard product > 0 else { return nil }
            let period = (bpmDiv / product).rounded(.down)
            guard period > 0 else { return nil }
            return period * 4 / ciaClockPAL
        }
        // SPD-Modus. Tempo ≤ 10 benutzt eine Tabelle der SoundTracker-Tempi;
        // die ist hier nicht umgesetzt, kommt im Material aber nicht vor.
        let tempo = Double(song.defaultTempo)
        guard tempo > 10 else { return nil }
        let period = (timerDiv / tempo).rounded(.down)
        guard period > 0 else { return nil }
        return period / ciaClockPAL
    }

    /// Dauer einer Pattern-Zeile in Sekunden. `mmd_counter` zählt bis
    /// `tempo2` (TPL), eine Zeile dauert also so viele Ticks.
    public static func rowDuration(song: Song) -> Double? {
        guard let t = tickDuration(song: song) else { return nil }
        return t * Double(song.ticksPerRow)
    }

    /// Notenlänge in Sekunden.
    ///
    /// **Am Original gemessen** (2026-10-01, BPM 33, TPL 6, LPB 8 — Zeile
    /// 227,25 ms, Tick 37,875 ms). Eine Note in Zeile 0, darunter 15 Zellen
    /// mit nur der Instrumentnummer (in OctaMED als senkrechter Strich
    /// gezeichnet):
    ///
    /// | `hold` | gemessene Länge | abzüglich `hold × Tick` |
    /// |---|---|---|
    /// | 1 | 3,446 s | 3,4081 s = 14,997 Zeilen |
    /// | 16 | 4,015 s | 3,4090 s = 15,001 Zeilen |
    /// | 64 | 5,832 s | 3,4080 s = 14,996 Zeilen |
    ///
    /// Daraus:
    ///
    ///     Notenlänge = Haltezeilen × Zeilendauer + hold × Tickdauer
    ///
    /// Die Haltezeilen sind die Zellen, die nur die Instrumentnummer tragen.
    /// Sie sind **Daten**, keine Editier-Überbleibsel — OctaMED stellt sie als
    /// Strich dar, und sie bestimmen die Grundlänge. `hold` kommt obendrauf,
    /// klingt also über die gezeichneten Striche hinaus. Der Autor:
    /// „die pipes sind schon mehrere zeilen vorbei — dann kommt das noteoff."
    ///
    /// Beendet wird die Note ausserdem durch `0F FF` oder die nächste Note auf
    /// derselben Spur; dann gilt der frühere Zeitpunkt.
    public static func noteDuration(holdRows: Int, hold: UInt8, song: Song) -> Double? {
        guard let tick = tickDuration(song: song) else { return nil }
        let row = tick * Double(song.ticksPerRow)
        return Double(holdRows) * row + Double(hold) * tick
    }

}
