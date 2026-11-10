import SwiftUI

/// The imported games. Import adds files through the system file picker; a
/// tap starts a game, which takes the library's place in the window
/// (`RootView`). Licenses and cores sit in the info menu.
struct LibraryView: View {
    /// Shows a game, or in debug builds a test pattern, in place of the library.
    let open: (RootView.Stage) -> Void
    @Environment(GameLibrary.self) private var library
    @State private var path = NavigationPath()
    @State private var isImporting = false
    @State private var importProblems: [ImportError] = []

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
            allowedContentTypes: GameSystem.all.flatMap(\.importTypes),
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { await importGames(from: urls) }
        }
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
                    Text("Import your own GBA or DS game files. Arcfold comes without games.",
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
                    open(.game(game))
                } label: {
                    LabeledContent {
                        Text(verbatim: GameSystem.system(id: game.system)?.name ?? game.system)
                    } label: {
                        Text(verbatim: game.name)
                    }
                }
                .tint(.primary)
                // With the system, because a GBA and a DS game may share a name.
                .accessibilityIdentifier("game-\(game.system)-\(game.name)")
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
                open(.game(outcome.game))
            }
        case .testPattern?:
            open(.testPattern)
        case let .layoutTestPattern(systemID)?:
            open(.layoutTestPattern(systemID: systemID))
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
    LibraryView { _ in }
        .environment(GameLibrary(previewing: [
            Game(id: "1", name: "Selftest", system: "gba", originalFileName: "selftest.gba",
                 size: 864, importedAt: .now),
            Game(id: "2", name: "Homebrew Demo", system: "gba", originalFileName: "demo.gba",
                 size: 61_104, importedAt: .now),
        ]))
}

#Preview("Empty") {
    LibraryView { _ in }
        .environment(GameLibrary(previewing: []))
}
