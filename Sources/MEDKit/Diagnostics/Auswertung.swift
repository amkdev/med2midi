import Foundation

extension MEDLoader {
    /// Befehlsstatistik, Warnungen und Hinweise über alle Blöcke.
    static func werteAus(blöcke: [Block], instrumente: [Instrument],
                         cmd3x: [(typ: UInt8, nummer: UInt16)],
                         lautstärkeHex: Bool, siebenBit: Bool,
                         in diagnose: inout Diagnose) {
        var statistik: [UInt8: Int] = [:]
        var fundstellen: [UInt8: [Fundstelle]] = [:]
        var unbekannt: [UInt8: (anzahl: Int, orte: [Fundstelle])] = [:]
        var ohneWirkung: [UInt8: Int] = [:]
        var velocityWerte: [UInt8: Int] = [:]
        var cmd3xFehlt: Set<UInt8> = []
        var notenProInstrument: [UInt8: Int] = [:]
        var werteProBefehl: [UInt8: Set<UInt8>] = [:]

        for block in blöcke {
            for zeile in 0..<block.zeilen {
                for spur in 0..<block.spuren {
                    let z = block.zelle(zeile: zeile, spur: spur)
                    if z.note > 0 && z.instrument > 0 {
                        notenProInstrument[z.instrument, default: 0] += 1
                    }
                    for seite in 0..<block.seitenAnzahl {
                        let b = block.befehl(zeile: zeile, spur: spur, seite: seite)
                        // Befehl 00 mit Datenbyte != 0 ist ein echter Befehl
                        // (MIDI-Controller-Wert) und darf nicht als leer gelten.
                        guard !b.istLeer else { continue }

                        statistik[b.nummer, default: 0] += 1
                        werteProBefehl[b.nummer, default: []].insert(b.daten)
                        let ort = Fundstelle(block: block.nummer, blockname: block.name,
                                             zeile: zeile, spur: spur, seite: seite)
                        if fundstellen[b.nummer, default: []].count < 8 {
                            fundstellen[b.nummer, default: []].append(ort)
                        }

                        switch Befehlskatalog.midiWirkung(b.nummer) {
                        case .unbekannt:
                            var e = unbekannt[b.nummer] ?? (0, [])
                            e.anzahl += 1
                            if e.orte.count < 5 { e.orte.append(ort) }
                            unbekannt[b.nummer] = e
                        case .ohneWirkungBeiMIDI:
                            ohneWirkung[b.nummer, default: 0] += 1
                        case .velocity:
                            velocityWerte[b.daten, default: 0] += 1
                        case .freierController:
                            if cmd3x.isEmpty { cmd3xFehlt.insert(b.nummer) }
                        default: break
                        }
                    }
                }
            }
        }

        for (nummer, e) in unbekannt.sorted(by: { $0.key < $1.key }) {
            diagnose.warnungen.append(Warnung(
                art: .unbekannterBefehl(nummer: nummer, daten: e.orte.first.map { _ in 0 } ?? 0),
                fundstellen: e.orte, anzahl: e.anzahl))
        }
        for (nummer, anzahl) in ohneWirkung.sorted(by: { $0.key < $1.key }) {
            diagnose.warnungen.append(Warnung(
                art: .befehlOhneWirkungBeiMIDI(nummer: nummer),
                fundstellen: fundstellen[nummer] ?? [], anzahl: anzahl))
        }
        for nummer in cmd3xFehlt.sorted() {
            diagnose.warnungen.append(Warnung(
                art: .cmd3xFehlt(befehl: nummer),
                fundstellen: fundstellen[nummer] ?? [], anzahl: statistik[nummer] ?? 0))
        }
        // Die Lesart der 0C-Werte hängt vom Block ab: trägt er eine
        // Befehlserweiterung, sind die Werte 7-bittig (0–127), sonst gilt
        // FLAG_VOLHEX. Dass dieselben Daten je nach Modus andere Velocities
        // ergeben, ist am Original gemessen.
        let gesamt = velocityWerte.values.reduce(0, +)
        if gesamt > 50, !siebenBit {
            let satt = velocityWerte
                .filter { Befehlskatalog.velocity(ausBefehlsdaten: $0.key,
                                                  lesart: lautstärkeHex ? .hexadezimal : .dezimal) >= 127 }
                .values.reduce(0, +)
            let quote = satt * 100 / gesamt
            if quote > 0 {
                diagnose.hinweise.append(Hinweis(
                    text: "\(quote) % der Velocities erreichen 127 "
                        + "(Lesart: \(lautstärkeHex ? "hexadezimal" : "dezimal"))"))
            }
        }

        // 0C ab 0x80 setzt die Grundlautstärke des Instruments statt einer
        // Notenlautstärke. In den Testdateien kommt das nicht vor.
        let grund = velocityWerte.filter { $0.key >= 0x80 }
        if !grund.isEmpty {
            diagnose.hinweise.append(Hinweis(
                text: "Befehl 0C mit Werten ab 0x80 (\(grund.values.reduce(0, +))×): "
                    + "setzt die Grundlautstärke des Instruments, nicht die Note"))
        }

        // Kanalbelegung: Warnung nur bei zwei KLINGENDEN Instrumenten.
        // Ein Paar aus klingendem Instrument und einem mit Lautstärke 0
        // (vom Autor "MidiControlChannel_…" genannt) ist Absicht.
        var proKanal: [UInt8: [Instrument]] = [:]
        for i in instrumente where i.istMIDI { proKanal[i.midiKanal, default: []].append(i) }
        for (kanal, liste) in proKanal.sorted(by: { $0.key < $1.key }) {
            let klingend = liste.filter(\.klingt)
            if klingend.count > 1 {
                diagnose.warnungen.append(Warnung(
                    art: .kanalKollision(kanal: kanal, instrumente: klingend.map(\.nummer)),
                    fundstellen: [], anzahl: klingend.count))
            } else if liste.count > 1 {
                let stumm = liste.filter { !$0.klingt }.map { "#\($0.nummer) \($0.name)" }
                diagnose.hinweise.append(Hinweis(
                    text: "Kanal \(kanal): Controller-Spur(en) \(stumm.joined(separator: ", ")) "
                        + "neben \(klingend.first.map { "#\($0.nummer) \($0.name)" } ?? "—")"))
            }
        }

        diagnose.befehlsStatistik = statistik
        diagnose.befehlsFundstellen = fundstellen
    }
}
