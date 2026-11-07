import Foundation
import LibretroKit

/// Reads name and version of every core embedded in the app.
nonisolated enum CoreCatalog {
    enum State: Sendable {
        case loading
        case loaded([EmbeddedCore])
        case noCores
        case failed(LibretroError)
    }

    /// Loads each core once and closes it again. `@concurrent` keeps every call
    /// into a core off the main thread (docs/PLAN.md, guardrail 4).
    @concurrent
    static func load(from bundle: Bundle = .main) async -> State {
        let names = LibretroCore.embeddedCoreNames(in: bundle)
        guard !names.isEmpty else { return .noCores }

        var cores: [EmbeddedCore] = []
        for name in names {
            do throws(LibretroError) {
                let core = try LibretroCore(named: name, in: bundle)
                let info = core.systemInfo()
                cores.append(EmbeddedCore(id: name, name: info.libraryName, version: info.libraryVersion))
            } catch {
                return .failed(error)
            }
        }
        return .loaded(cores)
    }
}

nonisolated struct EmbeddedCore: Identifiable, Sendable {
    /// The framework name, for example `mgba_libretro`.
    let id: String
    let name: String
    let version: String
}
