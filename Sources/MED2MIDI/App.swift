import SwiftUI
import UniformTypeIdentifiers
import MEDKit

@main
struct MED2MIDIApp: App {
    @State private var store = Store()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("MED2MIDI", id: "haupt") {
            Hauptansicht()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
                .task { NSApp.activate(ignoringOtherApps: true) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Öffnen …") { store.öffnenDialog() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Navigation") {
                Button("Nächster Block (Songreihenfolge)") { store.weiterInSongreihenfolge(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Voriger Block (Songreihenfolge)") { store.weiterInSongreihenfolge(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Blockanfang") { store.position.zeile = 0 }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
            }
        }
    }
}

struct Hauptansicht: View {
    @Environment(Store.self) private var store
    @State private var blockEingabe = ""

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            seitenleiste
        } detail: {
            if let geladen = store.aktiv {
                VStack(spacing: 0) {
                    werkzeugleiste(geladen.song)
                    Divider()
                    TabView {
                        patternSeite(geladen.song)
                            .tabItem { Label("Pattern", systemImage: "tablecells") }
                        SonginfoAnsicht(song: geladen.song)
                            .tabItem { Label("Song", systemImage: "info.circle") }
                    }
                }
            } else {
                leerAnsicht
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.lade(urls.filter { $0.isFileURL }); return true
        }
        .alert("Fehler beim Laden", isPresented: .init(
            get: { store.fehler != nil }, set: { if !$0 { store.fehler = nil } })
        ) {
            Button("OK") { store.fehler = nil }
        } message: { Text(store.fehler ?? "") }
    }

    private var leerAnsicht: some View {
        VStack(spacing: 12) {
            Image(systemName: "pianokeys").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Songs hierher ziehen oder ⌘O").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var seitenleiste: some View {
        @Bindable var store = store
        return List(selection: $store.auswahl) {
            ForEach(store.songs) { g in
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.url.lastPathComponent).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(g.song.version.name)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.quaternary, in: .rect(cornerRadius: 3))
                        if !g.song.diagnose.warnungen.isEmpty {
                            Label("\(g.song.diagnose.warnungen.count)",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption2)
                }
                .tag(g.id)
                .contextMenu {
                    Button("Schließen") { store.schließe(g.id) }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 230)
        .onChange(of: store.auswahl) { _, _ in store.springeAnSongAnfang() }
    }

    private func werkzeugleiste(_ song: Song) -> some View {
        @Bindable var store = store
        let folge = store.songFolge
        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                Button { store.weiterInSongreihenfolge(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(store.position.sequenzPosition <= 0)
                Text("Sequenz \(store.position.sequenzPosition + 1)/\(max(folge.count, 1))")
                    .font(.callout.monospacedDigit())
                Button { store.weiterInSongreihenfolge(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.position.sequenzPosition >= folge.count - 1)
            }

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                Text("Block")
                TextField("", text: $blockEingabe)
                    .frame(width: 46)
                    .onSubmit { if let n = Int(blockEingabe) { store.zuBlock(n) } }
                Text("/ \(song.blöcke.count - 1)").foregroundStyle(.secondary)
            }

            if let b = store.aktiverBlock, b.seitenAnzahl > 1 {
                Divider().frame(height: 18)
                Picker("Seite", selection: $store.position.seite) {
                    ForEach(0..<b.seitenAnzahl, id: \.self) { Text("Seite \($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 180)
            }

            Spacer()

            positionsanzeige
            Toggle("Farben", isOn: $store.spurenEinfärben).toggleStyle(.switch)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .onChange(of: store.position.block) { _, neu in blockEingabe = "\(neu)" }
        .onAppear { blockEingabe = "\(store.position.block)" }
    }

    private var positionsanzeige: some View {
        HStack(spacing: 10) {
            beschriftet("Zeile", String(format: "%03d", store.position.zeile))
            beschriftet("Takt.Beat", store.taktUndBeat)
            beschriftet("Zeit", store.zeitImBlock)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func beschriftet(_ name: String, _ wert: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(wert)
        }
    }

    private func patternSeite(_ song: Song) -> some View {
        Group {
            if let block = store.aktiverBlock, block.zeilen > 0 {
                VStack(spacing: 0) {
                    HStack {
                        Text("Block \(block.nummer)")
                            .font(.headline)
                        if !block.name.isEmpty {
                            Text("„\(block.name)“").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(block.spuren) Spuren · \(block.zeilen) Zeilen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    PatternAnsicht(song: song, block: block)
                }
            } else {
                Text("Block \(store.position.block) ist leer")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
