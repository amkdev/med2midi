import SwiftUI
import MEDKit

/// Tracker-Darstellung eines Blocks, so nah wie möglich an OctaMED.
///
/// Zellenformat aus einem Bildschirmfoto von OctaMED SoundStudio V1.03c
/// abgeleitet: Notenname (3 Zeichen), Instrument (eine Hexziffer),
/// Befehl (2) und Datenbyte (2) — zum Beispiel `E-5 A0000`.
struct PatternAnsicht: View {
    @Environment(Store.self) private var store
    @FocusState private var hatFokus: Bool
    let song: Song
    let block: Block

    private let zeilenHöhe: CGFloat = 16
    private let zeilenNrBreite: CGFloat = 46
    private let spurBreite: CGFloat = 86

    var body: some View {
        VStack(spacing: 0) {
            kopfzeile
            Divider()
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<block.zeilen, id: \.self) { zeile in
                            zeilenAnsicht(zeile)
                                .id(zeile)
                        }
                    }
                }
                .onChange(of: store.position.zeile) { _, neu in
                    withAnimation(.linear(duration: 0.08)) {
                        proxy.scrollTo(neu, anchor: .center)
                    }
                }
                .onChange(of: store.position.block) { _, _ in
                    proxy.scrollTo(0, anchor: .top)
                }
            }
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .background(Color.black)
        // Tastaturbedienung: die Ansicht muss fokussierbar sein, sonst
        // bekommt sie keine Tastendrücke.
        .focusable()
        .focusEffectDisabled()
        .focused($hatFokus)
        .onAppear { hatFokus = true }
        .onTapGesture { hatFokus = true }
        .onKeyPress(.upArrow)    { store.zeileVerschieben(-1); return .handled }
        .onKeyPress(.downArrow)  { store.zeileVerschieben(1);  return .handled }
        .onKeyPress(.pageUp)     { store.zeileVerschieben(-store.seitenSprung); return .handled }
        .onKeyPress(.pageDown)   { store.zeileVerschieben(store.seitenSprung);  return .handled }
        .onKeyPress(.home)       { store.position.zeile = 0; return .handled }
        .onKeyPress(.end)        { store.position.zeile = max(0, block.zeilen - 1); return .handled }
        .onKeyPress(.leftArrow)  { store.weiterInSongreihenfolge(-1); return .handled }
        .onKeyPress(.rightArrow) { store.weiterInSongreihenfolge(1);  return .handled }
        .onKeyPress(.tab) {
            if block.seitenAnzahl > 1 {
                store.position.seite = (store.position.seite + 1) % block.seitenAnzahl
            }
            return .handled
        }
    }

    private var kopfzeile: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: zeilenNrBreite)
            ForEach(0..<block.spuren, id: \.self) { spur in
                VStack(spacing: 1) {
                    Text("\(spur)")
                        .foregroundStyle(.secondary)
                    Text(instrumentNameDerSpur(spur))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(farbeDerSpur(spur))
                        .lineLimit(1)
                }
                .frame(width: spurBreite)
            }
        }
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func zeilenAnsicht(_ zeile: Int) -> some View {
        let istAktuell = zeile == store.position.zeile
        let istBeat = song.zeilenProBeat > 0 && zeile % song.zeilenProBeat == 0
        return HStack(spacing: 0) {
            Text(String(format: "%03d", zeile))
                .foregroundStyle(istBeat ? .primary : .secondary)
                .frame(width: zeilenNrBreite, alignment: .center)
            ForEach(0..<block.spuren, id: \.self) { spur in
                zelleAnsicht(zeile: zeile, spur: spur)
                    .frame(width: spurBreite, alignment: .leading)
            }
        }
        .frame(height: zeilenHöhe)
        .background(
            istAktuell ? Color.accentColor.opacity(0.35)
                       : (istBeat ? Color.white.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { store.position.zeile = zeile; hatFokus = true }
    }

    private func zelleAnsicht(zeile: Int, spur: Int) -> some View {
        let z = block.zelle(zeile: zeile, spur: spur)
        let b = block.befehl(zeile: zeile, spur: spur, seite: store.position.seite)
        return HStack(spacing: 0) {
            Text(z.notenName)
                .foregroundStyle(z.note > 0 ? Color(nsColor: .white) : Color.gray.opacity(0.45))
            Text(" ")
            Text(PatternDarstellung.instrumentZeichen(z.instrument))
                .foregroundStyle(z.instrument > 0 ? farbeDesInstruments(z.instrument)
                                                  : Color.gray.opacity(0.45))
            Text(b.hex)
                .foregroundStyle(befehlsFarbe(b))
        }
        .help(erklärung(zelle: z, befehl: b))
    }

    // MARK: - Erklärung beim Überfahren

    private func erklärung(zelle: Zelle, befehl: Befehl) -> String {
        var teile: [String] = []
        if zelle.note > 0 { teile.append("Note \(zelle.notenName)") }
        if zelle.instrument > 0 {
            let i = instrument(zelle.instrument)
            let name = i?.name.isEmpty == false ? " „\(i!.name)“" : ""
            let kanal = i.map { $0.istMIDI ? "MIDI-Kanal \($0.midiKanal)" : "kein MIDI-Kanal" } ?? ""
            teile.append("Instrument \(zelle.instrument)\(name) — \(kanal)")
        }
        if !befehl.istLeer {
            teile.append("\(befehl.hex): \(Befehlskatalog.erklärung(befehl))")
        }
        return teile.isEmpty ? "leer" : teile.joined(separator: "\n")
    }

    // MARK: - Farben

    private func instrument(_ nummer: UInt8) -> Instrument? {
        let i = Int(nummer) - 1
        return i >= 0 && i < song.instrumente.count ? song.instrumente[i] : nil
    }

    /// Welches Instrument prägt diese Spur? (häufigstes im Block)
    private func instrumentDerSpur(_ spur: Int) -> UInt8? {
        var zähler: [UInt8: Int] = [:]
        for zeile in 0..<block.zeilen {
            let ins = block.zelle(zeile: zeile, spur: spur).instrument
            if ins > 0 { zähler[ins, default: 0] += 1 }
        }
        return zähler.max { $0.value < $1.value }?.key
    }

    private func instrumentNameDerSpur(_ spur: Int) -> String {
        guard let nr = instrumentDerSpur(spur), let i = instrument(nr) else { return "—" }
        if !i.name.isEmpty { return i.name }
        return i.istMIDI ? "ch\(i.midiKanal)" : "#\(i.nummer)"
    }

    private func farbeDerSpur(_ spur: Int) -> Color {
        guard let nr = instrumentDerSpur(spur) else { return .secondary }
        return farbeDesInstruments(nr)
    }

    private static let palette: [Color] = [
        .init(red: 0.45, green: 0.78, blue: 1.00), .init(red: 0.98, green: 0.72, blue: 0.40),
        .init(red: 0.58, green: 0.87, blue: 0.60), .init(red: 0.96, green: 0.60, blue: 0.68),
        .init(red: 0.75, green: 0.68, blue: 0.98), .init(red: 0.52, green: 0.90, blue: 0.86),
        .init(red: 0.93, green: 0.85, blue: 0.48), .init(red: 0.86, green: 0.64, blue: 0.94),
    ]

    private func farbeDesInstruments(_ nummer: UInt8) -> Color {
        guard store.spurenEinfärben else { return Color(nsColor: .lightGray) }
        return Self.palette[Int(nummer) % Self.palette.count]
    }

    /// Befehle nach Wirkung einfärben — Lautstärke, Tonhöhe, Struktur, Rest.
    private func befehlsFarbe(_ b: Befehl) -> Color {
        if b.istLeer { return Color.gray.opacity(0.35) }
        switch Befehlskatalog.midiWirkung(b.nummer) {
        case .velocity, .lautstärkeController, .controllerWert, .controllerNummer,
             .pan, .modulationsrad, .freierController:
            return .init(red: 0.55, green: 0.85, blue: 0.55)
        case .pitchbendAuf, .pitchbendAb, .pitchbendSetzen,
             .polyphonerAftertouch, .kanalAftertouch:
            return .init(red: 0.95, green: 0.78, blue: 0.45)
        case .tempoOderSonderfall, .ticksProZeile, .sprungNächsteSequenz,
             .playseqSprung, .blockWiederholen, .zeileWiederholen:
            return .init(red: 0.60, green: 0.75, blue: 1.00)
        case .sysexSenden, .midiPreset:
            return .init(red: 0.95, green: 0.55, blue: 0.95)
        case .unbekannt, .ohneWirkungBeiMIDI:
            return .init(red: 1.00, green: 0.45, blue: 0.45)
        default:
            return Color(nsColor: .lightGray)
        }
    }
}
