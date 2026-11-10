#if DEBUG
import FoldLayout
import Foundation

/// Launch arguments for UI tests and acceptance runs in the Simulator, in
/// debug builds only (ADR 0005, section 9; ADR 0006, section 15):
///
/// - `-ArcfoldAutorun <path>` imports the file the same way as the file
///   importer and starts it.
/// - `-ArcfoldImport <path>` only imports it.
/// - `-ArcfoldTestPattern YES` shows the game screen with the test pattern of
///   M1 instead of a core, fitted without a layout.
/// - `-ArcfoldTestPattern ds` or `gba` shows the game view of that system
///   with a test pattern instead of a core, in the layout of the pose.
/// - `-ArcfoldFoldOverride flat`, `tabletop` or `book` replaces the measured
///   fold with an artificial one, for layouts on the inner display. It never
///   affects the pause, which follows the hinge.
///
/// The requests are read once per process.
enum DebugLaunch {
    enum Request: Equatable {
        case importGame(URL, start: Bool)
        case testPattern
        case layoutTestPattern(systemID: String)
    }

    private static var isConsumed = false

    /// The request of the launch arguments, the first time only.
    static func consume(from defaults: UserDefaults = .standard) -> Request? {
        guard !isConsumed else { return nil }
        isConsumed = true
        if let path = defaults.string(forKey: "ArcfoldAutorun"), !path.isEmpty {
            return .importGame(URL(filePath: path), start: true)
        }
        if let path = defaults.string(forKey: "ArcfoldImport"), !path.isEmpty {
            return .importGame(URL(filePath: path), start: false)
        }
        if let pattern = defaults.string(forKey: "ArcfoldTestPattern")?.lowercased() {
            if let system = GameSystem.system(id: pattern) {
                return .layoutTestPattern(systemID: system.id)
            }
            if defaults.bool(forKey: "ArcfoldTestPattern") {
                return .testPattern
            }
        }
        return nil
    }

    /// The artificial fold of `-ArcfoldFoldOverride`, nil without the argument.
    static let foldOverride: FoldOverride? = UserDefaults.standard.string(forKey: "ArcfoldFoldOverride")
        .flatMap { FoldOverride(rawValue: $0.lowercased()) }
}

/// An artificial fold across the middle of the view (ADR 0006, section 15).
/// Meant for the inner display; on the outer display it gives degenerate
/// layouts, which is what such a fold would mean there.
enum FoldOverride: String, Sendable {
    /// Open flat: an inactive fold, from top to bottom when the view is wider
    /// than high, across otherwise.
    case flat
    /// Folded with the fold across the view, 16 pt wide, active.
    case tabletop
    /// Folded like a book: from top to bottom, 16 pt wide, active.
    case book

    /// The band of a folded device as ADR 0006 assumes it for the Simulator.
    static let band = 16

    func applied(to geometry: FoldGeometry) -> FoldGeometry {
        var geometry = geometry
        let size = geometry.container
        let band = Self.band * geometry.scale
        switch self {
        case .flat where size.isLandscape:
            geometry.fold = PixelRect(x: size.width / 2, y: 0, width: 0, height: size.height)
            geometry.isFoldActive = false
        case .flat:
            geometry.fold = PixelRect(x: 0, y: size.height / 2, width: size.width, height: 0)
            geometry.isFoldActive = false
        case .tabletop:
            geometry.fold = PixelRect(x: 0, y: (size.height - band) / 2, width: size.width, height: band)
            geometry.isFoldActive = true
        case .book:
            geometry.fold = PixelRect(x: (size.width - band) / 2, y: 0, width: band, height: size.height)
            geometry.isFoldActive = true
        }
        geometry.foldMargins = .zero
        return geometry
    }
}
#endif
