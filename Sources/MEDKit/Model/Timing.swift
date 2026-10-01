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

    /// Notenlänge aus dem Hold-Wert.
    ///
    /// **Am Original gemessen** (2026-10-01): Bei SPD-Tempo 33 ergaben
    /// `hold = 1` und `hold = 32` Notenlängen von 1,656 s und 2,276 s. Die
    /// Differenz von 0,620 s entspricht 31 Ticks × 0,02008 s = 0,6224 s —
    /// Abweichung 0,4 %. **Hold zählt Ticks.**
    ///
    /// Beide Messungen zerlegen sich als `1,634 s + hold × Tickdauer`; der
    /// gleichbleibende Sockel war das, was die Note sonst beendet hat. Hold
    /// wirkt also zusätzlich, nicht ausschliesslich.
    public static func holdDuration(hold: UInt8, song: Song) -> Double? {
        guard hold > 0, let t = tickDuration(song: song) else { return nil }
        return Double(hold) * t
    }
}
