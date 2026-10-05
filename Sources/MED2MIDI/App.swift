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
            MainView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
                .task { NSApp.activate(ignoringOtherApps: true) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Öffnen …") { store.showOpenPanel() }
                    .keyboardShortcut("o")
                Divider()
                Button("Exportieren") { store.exportCurrent() }
                    .keyboardShortcut("e")
                    .disabled(store.current == nil || store.exporting)
                Button(store.selection.count > 1
                       ? "Auswahl exportieren" : "Alle Songs exportieren") { store.exportAll() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.batchSongs.count < 2 || store.exporting)
                Divider()
                Button(store.selection.count > 1
                       ? "\(store.selection.count) Songs entfernen" : "Song entfernen") {
                    store.closeSelected()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(store.selection.isEmpty)
                Button("Alle entfernen") { store.closeAll() }
                    .disabled(store.songs.isEmpty)
            }
            CommandMenu("Navigation") {
                Button("Nächster Block (Songreihenfolge)") { store.stepInSongOrder(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Voriger Block (Songreihenfolge)") { store.stepInSongOrder(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Blockanfang") { store.position.row = 0 }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
            }
        }
    }
}

struct MainView: View {
    @Environment(Store.self) private var store
    @State private var blockInput = ""

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            sidebar
        } detail: {
            if let loaded = store.current {
                VStack(spacing: 0) {
                    toolbar(loaded.song)
                    Divider()
                    TabView {
                        patternTab(loaded.song)
                            .tabItem { Label("Pattern", systemImage: "tablecells") }
                        SongInfoView(song: loaded.song)
                            .tabItem { Label("Song", systemImage: "info.circle") }
                    }
                }
            } else {
                emptyView
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            // Über `accept`, nicht `load`: Ein abgelegter Ordner muss erst
            // durchsucht werden, sonst scheitert er mit „Is a directory".
            store.accept(urls)
            return true
        }
        .overlay {
            if store.scanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Ordner wird durchsucht …").font(.callout)
                }
                .padding(24)
                .background(.regularMaterial, in: .rect(cornerRadius: 10))
            }
        }
        .alert("Fehler beim Laden", isPresented: .init(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "pianokeys").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Songs hierher ziehen oder ⌘O").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Seitenleiste: oben die geladenen Songs, darunter die Spielsequenz —
    /// wie OctaMEDs gleichnamiges Fenster, nur fest eingebaut.
    private var sidebar: some View {
        VSplitView {
            songList
                .frame(minHeight: 80, idealHeight: 150)
            sequenceList
                .frame(minHeight: 140)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 250)
    }

    /// Die Spielsequenz, wie OctaMED sie zeigt: laufende Nummer, Blocknummer,
    /// Blockname. Derselbe Block kann mehrfach vorkommen — die Position ist
    /// das, was zählt.
    private var sequenceList: some View {
        let order = store.songOrder
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Spielsequenz").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(order.count)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)

            Divider()

            ScrollViewReader { leser in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(order.enumerated()), id: \.offset) { position, block in
                            sequenceRow(position: position, block: block)
                                .id(position)
                        }
                    }
                }
                .onChange(of: store.position.sequencePosition) { _, neu in
                    withAnimation(.easeOut(duration: 0.15)) { leser.scrollTo(neu, anchor: .center) }
                }
            }
        }
    }

    private func sequenceRow(position: Int, block: Int) -> some View {
        let song = store.current?.song
        let b = song.flatMap { block < $0.blocks.count ? $0.blocks[block] : nil }
        let aktuell = position == store.position.sequencePosition
        let sendeblock = b?.isSysExSendBlock == true
        return HStack(spacing: 6) {
            Text(String(format: "%03d", position + 1))
                .foregroundStyle(aktuell ? .primary : .tertiary)
            Text(String(format: "%03d:", block))
                .foregroundStyle(aktuell ? .primary : .secondary)
            Text(b.map { $0.name.isEmpty ? "—" : $0.name } ?? "fehlt")
                .foregroundStyle(sendeblock ? .secondary : .primary)
                .italic(sendeblock)
                .lineLimit(1)
            Spacer(minLength: 0)
            if sendeblock {
                Image(systemName: "paperplane")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Sendeblock: schickt nur den SysEx-Dump, keine Musik")
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 10).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(aktuell ? Color.accentColor.opacity(0.3) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { store.goToSequencePosition(position) }
    }

    private var songList: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Songs").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if store.selection.count > 1 {
                    Text("\(store.selection.count) ausgewählt")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(store.songs.count)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            Divider()
            songTable
        }
    }

    private var songTable: some View {
        @Bindable var store = store
        return List(selection: $store.selection) {
            ForEach(store.songs) { g in
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.url.lastPathComponent).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(g.song.version.name)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.quaternary, in: .rect(cornerRadius: 3))
                        if !g.song.diagnostics.warnings.isEmpty {
                            Label("\(g.song.diagnostics.warnings.count)",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption2)
                }
                .tag(g.id)
                .contextMenu {
                    // Betrifft die ganze Auswahl, wenn die angeklickte Zeile
                    // dazugehört — sonst nur diese eine. So verhalten sich
                    // Listen auf dem Mac überall.
                    let betroffen: Set<LoadedSong.ID> =
                        store.selection.contains(g.id) ? store.selection : [g.id]
                    Button(betroffen.count > 1
                           ? "\(betroffen.count) Songs entfernen" : "Entfernen") {
                        store.close(betroffen)
                    }
                    Divider()
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([g.url])
                    }
                }
            }
        }
        .onChange(of: store.current?.id) { _, _ in store.goToSongStart() }
        .onDeleteCommand { store.closeSelected() }
        .sheet(item: $store.exportReport) { bericht in
            VStack(alignment: .leading, spacing: 14) {
                Label(bericht.failed ? "Export fehlgeschlagen" : "Export abgeschlossen",
                      systemImage: bericht.failed ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.headline)
                    .foregroundStyle(bericht.failed ? Color.orange : Color.green)

                Text(bericht.folder.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(bericht.lines.enumerated()), id: \.offset) { _, zeile in
                            Text(zeile)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)

                HStack {
                    if !bericht.failed {
                        Button("Im Finder zeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting([bericht.folder])
                        }
                    }
                    Spacer()
                    Button("Fertig") { store.exportReport = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 560)
        }
    }

    private func toolbar(_ song: Song) -> some View {
        @Bindable var store = store
        let order = store.songOrder
        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                Button { store.stepInSongOrder(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(store.position.sequencePosition <= 0)
                Text("Sequenz \(store.position.sequencePosition + 1)/\(max(order.count, 1))")
                    .font(.callout.monospacedDigit())
                Button { store.stepInSongOrder(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.position.sequencePosition >= order.count - 1)
            }

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                Text("Block")
                TextField("", text: $blockInput)
                    .frame(width: 46)
                    .onSubmit { if let n = Int(blockInput) { store.goToBlock(n) } }
                Text("/ \(song.blocks.count - 1)").foregroundStyle(.secondary)
            }

            if let b = store.currentBlock, b.pageCount > 1 {
                Divider().frame(height: 18)
                Picker("Seite", selection: $store.position.page) {
                    ForEach(0..<b.pageCount, id: \.self) { Text("Seite \($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 180)
            }

            Spacer()

            positionDisplay

            Divider().frame(height: 18)
            exportButton
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .onChange(of: store.position.block) { _, neu in blockInput = "\(neu)" }
        .onAppear { blockInput = "\(store.position.block)" }
    }

    /// Export mit gemerktem Zielordner. Der Pfeil daneben wählt einen neuen.
    private var exportButton: some View {
        HStack(spacing: 2) {
            Button {
                store.exportCurrent()
            } label: {
                if let p = store.exportProgress {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("\(p.done)/\(p.total)").font(.caption.monospacedDigit())
                    }
                } else if store.exporting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(store.exporting)
            .help(store.exportFolder.map { "Zielordner wählen — zuletzt: \($0.path)" }
                  ?? "Zielordner wählen und exportieren")

            Menu {
                Button(store.selection.count > 1
                       ? "Auswahl exportieren (\(store.selection.count))"
                       : "Alle \(store.songs.count) Songs exportieren") { store.exportAll() }
                    .disabled(store.batchSongs.count < 2)
                if let ordner = store.exportFolder {
                    Divider()
                    Text("Zuletzt: \(ordner.lastPathComponent)")
                    Button("Zuletzt verwendeten Ordner im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([ordner])
                    }
                }
            } label: { EmptyView() }
            .menuStyle(.borderlessButton)
            .frame(width: 14)
            .disabled(store.exporting)
        }
    }

    private var positionDisplay: some View {
        HStack(spacing: 10) {
            labelled("Zeile", String(format: "%03d / %03d", store.position.row,
                                        max(0, (store.currentBlock?.rows ?? 1) - 1)))
            labelled("Takt.Beat", store.barAndBeat)
            labelled("Zeit", store.timeInBlock)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func labelled(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func patternTab(_ song: Song) -> some View {
        Group {
            if let block = store.currentBlock, block.rows > 0 {
                VStack(spacing: 0) {
                    HStack {
                        Text("Block \(block.number)")
                            .font(.headline)
                        if !block.name.isEmpty {
                            Text("„\(block.name)“").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(block.tracks) Spuren · \(block.rows) Zeilen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    PatternView(song: song, block: block)
                }
            } else {
                Text("Block \(store.position.block) ist leer")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
