import SwiftUI

/// The imported games. Import adds files through the system file picker; a
/// tap starts a game full screen. Licenses and cores sit in the info menu.
struct LibraryView: View {
    @Environment(GameLibrary.self) private var library
    @State private var path = NavigationPath()
    @State private var isImporting = false
    @State private var importProblems: [ImportError] = []
    @State private var playing: Game?
    #if DEBUG
    @State private var showsTestPattern = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(Text("Library", comment: "Title of the list of imported games."))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                path.append(InfoPage.licenses)
                            } label: {
                                Label {
                                    Text("Licenses", comment: "Menu item that opens the license notices.")
                                } icon: {
                                    Image(systemName: "doc.text")
                                }
                            }
                            Button {
                                path.append(InfoPage.cores)
                            } label: {
                                Label {
                                    Text("Cores", comment: "Menu item that lists the embedded emulation cores.")
                                } icon: {
                                    Image(systemName: "cpu")
                                }
                            }
                        } label: {
                            Label {
                                Text("Info", comment: "Menu with licenses and cores.")
                            } icon: {
                                Image(systemName: "info.circle")
                            }
                        }
                        .accessibilityIdentifier("info-menu")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isImporting = true
                        } label: {
                            Label {
                                Text("Import", comment: "Button that adds game files to the library.")
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                        .accessibilityIdentifier("import")
                    }
                }
                .navigationDestination(for: InfoPage.self) { page in
                    switch page {
                    case .licenses: LicensesView()
                    case .cores: CoreListView()
                    }
                }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: GameSystem.all.map(\.contentType),
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { await importGames(from: urls) }
        }
        .fullScreenCover(item: $playing) { game in
            GameView(game: game, library: library)
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showsTestPattern) {
            TestPatternView()
        }
        #endif
        .alert(
            Text("Some Files Were Not Imported", comment: "Title of the alert after a failed import."),
            isPresented: Binding(get: { !importProblems.isEmpty }, set: { if !$0 { importProblems = [] } })
        ) {
            Button(role: .cancel) {
                importProblems = []
            } label: {
                Text("OK", comment: "Closes the import alert.")
            }
        } message: {
            Text(verbatim: importProblems.map(\.message).joined(separator: "\n"))
        }
        .task {
            await library.reload()
            #if DEBUG
            await runDebugLaunch()
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.games.isEmpty {
            if library.hasLoaded {
                ContentUnavailableView {
                    Label {
                        Text("No Games", comment: "Title of the empty library.")
                    } icon: {
                        Image(systemName: "square.stack")
                    }
                } description: {
                    Text("Import your own GBA game files. Arcfold comes without games.",
                         comment: "Explanation of the empty library.")
                } actions: {
                    Button {
                        isImporting = true
                    } label: {
                        Text("Import Games", comment: "Button in the empty library that opens the file picker.")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        } else {
            List(library.games) { game in
                Button {
                    playing = game
                } label: {
                    LabeledContent {
                        Text(verbatim: GameSystem.system(id: game.system)?.name ?? game.system)
                    } label: {
                        Text(verbatim: game.name)
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("game-\(game.name)")
            }
        }
    }

    /// The same way as the file picker: import, then show any problems.
    @discardableResult
    private func importGames(from urls: [URL]) async -> [Result<ImportOutcome, ImportError>] {
        let results = await library.importGames(from: urls)
        importProblems = results.compactMap { result in
            if case let .failure(error) = result { error } else { nil }
        }
        return results
    }

    #if DEBUG
    private func runDebugLaunch() async {
        switch DebugLaunch.consume() {
        case let .importGame(url, start)?:
            let results = await importGames(from: [url])
            if start, case let .success(outcome)? = results.first {
                playing = outcome.game
            }
        case .testPattern?:
            showsTestPattern = true
        case nil:
            break
        }
    }
    #endif
}

private enum InfoPage: Hashable {
    case licenses
    case cores
}

#Preview("Games") {
    LibraryView()
        .environment(GameLibrary(previewing: [
            Game(id: "1", name: "Selftest", system: "gba", originalFileName: "selftest.gba",
                 size: 864, importedAt: .now),
            Game(id: "2", name: "Homebrew Demo", system: "gba", originalFileName: "demo.gba",
                 size: 61_104, importedAt: .now),
        ]))
}

#Preview("Empty") {
    LibraryView()
        .environment(GameLibrary(previewing: []))
}
