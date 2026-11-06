#if DEBUG
import Foundation

/// Launch arguments for UI tests and acceptance runs in the Simulator, in
/// debug builds only (ADR 0005, section 9):
///
/// - `-ArcfoldAutorun <path>` imports the file the same way as the file
///   importer and starts it.
/// - `-ArcfoldImport <path>` only imports it.
/// - `-ArcfoldTestPattern YES` shows the game screen with a test pattern
///   instead of a core.
///
/// Read once per process.
enum DebugLaunch {
    enum Request: Equatable {
        case importGame(URL, start: Bool)
        case testPattern
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
        if defaults.bool(forKey: "ArcfoldTestPattern") {
            return .testPattern
        }
        return nil
    }
}
#endif
