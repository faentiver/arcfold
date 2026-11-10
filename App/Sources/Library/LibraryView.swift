import FoldLayout
import SwiftUI

/// The imported games as a grid of generated tiles. Import adds files
/// through the system file picker; a tap starts a game, which takes the
/// library's place in the window (`RootView`), so there is no presentation
/// and no zoom from the tile (ADR 0007, decision 11). Sorting, licenses and
/// cores sit in the More menu. Toolbar, menus, search and alerts carry the
/// system's glass; this view sets none of its own (ADR 0007).
struct LibraryView: View {
    /// Shows a game, or in debug builds a test pattern, in place of the library.
    let open: (RootView.Stage) -> Void
    @Environment(GameLibrary.self) private var library
    @State private var path = NavigationPath()
    @State private var isImporting = false
    @State private var importProblems: [ImportError] = []
    @State private var query = ""
    /// The scroll view of the grid as the system lays it out, and the
    /// margins the system keeps in it; both unknown until it appears.
    @State private var geometry: FoldGeometry?
    @State private var margins: SystemMargins?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("LibrarySort") private var sort = LibrarySort.name

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(Text("Library", comment: "Title of the list of imported games."))
                .toolbar {
                    // Both in .primaryAction: on the outer display they become
                    // one glass capsule in the system column (measured).
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker(selection: $sort) {
                                Text("Name", comment: "Library sort order by game name.")
                                    .tag(LibrarySort.name)
                                Text("Recently Added", comment: "Library sort order, newest import first.")
                                    .tag(LibrarySort.recentlyAdded)
                            } label: {
                                Label {
                                    Text("Sort By", comment: "Picker in the More menu that orders the library.")
                                } icon: {
                                    Image(systemName: "arrow.up.arrow.down")
                                }
                            }
                            .pickerStyle(.menu)
                            Section {
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
                            }
                        } label: {
                            Label {
                                Text("More", comment: "Toolbar menu of the library with sorting, licenses and cores.")
                            } icon: {
                                Image(systemName: "ellipsis")
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
                .modifier(LibrarySearch(isAvailable: !library.games.isEmpty, query: $query))
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
                        Image(systemName: "gamecontroller")
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
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                // Held like a book: beside the fold, not on it.
                .onFirstFoldPage()
            } else {
                ProgressView()
            }
        } else {
            let games = LibraryArrangement.arranged(library.games, sort: sort, query: query)
            ScrollView {
                if let space {
                    GameGrid(games: games, space: space) { game in
                        open(.game(game))
                    }
                    .padding(.top, LibraryColumns.topPadding)
                    .padding(.bottom, 24)
                }
            }
            .onFoldGeometryChange(scale: max(1, Int(displayScale.rounded()))) { geometry = $0 }
            // The grid begins where the large title does: at the margins of
            // the system, which no SwiftUI value carries.
            .background {
                SystemMarginsReader { margins = $0 }
                    .accessibilityHidden(true)
            }
            .overlay {
                if games.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .onFirstFoldPage()
                }
            }
        }
    }

    /// The room of the grid, once the scroll view and the margins are known.
    private var space: LibraryColumns.Space? {
        guard var geometry, let margins else { return nil }
        #if DEBUG
        // The artificial fold of debug builds, as in a game.
        geometry = DebugRemote.shared.foldOverride?.applied(to: geometry) ?? geometry
        #endif
        return LibraryColumns.Space(geometry: geometry, margins: margins, isRightToLeft: layoutDirection == .rightToLeft)
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

/// The search field, only while there are games: otherwise the magnifier
/// would stand alone at the bottom of the system column (measured).
private struct LibrarySearch: ViewModifier {
    let isAvailable: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isAvailable {
            content
                .searchable(text: $query, prompt: Text("Search Games", comment: "Prompt of the search field in the library."))
                .searchToolbarBehavior(.minimize)
        } else {
            content
        }
    }
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

#Preview("Inner display", traits: .fixedLayout(width: 669, height: 951)) {
    LibraryView { _ in }
        .environment(GameLibrary(previewing: (1...7).map { index in
            Game(id: "\(index)", name: "Game \(index)", system: "gba", originalFileName: "game.gba",
                 size: 1024, importedAt: .now)
        }))
}
