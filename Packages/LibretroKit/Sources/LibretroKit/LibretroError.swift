/// An error while loading a libretro core.
public enum LibretroError: Error, Hashable, CustomStringConvertible {
    /// The bundle contains no framework with this name, or it has no executable.
    case frameworkNotFound(name: String, path: String)

    /// `dlopen` rejected the framework. `reason` is the message from `dlerror`.
    case loadFailed(name: String, reason: String)

    /// The core does not export a required function. `reason` is the message from `dlerror`.
    case symbolNotFound(name: String, symbol: String, reason: String)

    public var description: String {
        switch self {
        case let .frameworkNotFound(name, path):
            "Core \(name) not found at \(path)"
        case let .loadFailed(name, reason):
            "Core \(name) could not be loaded: \(reason)"
        case let .symbolNotFound(name, symbol, reason):
            "Core \(name) does not export \(symbol): \(reason)"
        }
    }
}
