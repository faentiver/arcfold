internal import CLibretro
import Darwin
import Foundation

/// A libretro core, loaded at runtime from its framework inside an app bundle.
///
/// Every core is a dynamic framework in the app's `Frameworks` folder. All cores
/// export the same `retro_*` functions, so the app never links them. This type
/// opens one core with `dlopen` and resolves the functions it needs with `dlsym`.
/// Dropping the value closes the library again.
public struct LibretroCore: ~Copyable {
    /// The libretro API version this host is built against (`RETRO_API_VERSION`).
    public static let hostAPIVersion = UInt32(RETRO_API_VERSION)

    /// The framework name, for example `mgba_libretro`.
    public let name: String

    private let handle: UnsafeMutableRawPointer
    private let retroAPIVersion: @convention(c) () -> CUnsignedInt
    private let retroGetSystemInfo: @convention(c) (UnsafeMutablePointer<retro_system_info>?) -> Void
    /// The rest of the libretro API that a session calls (LibretroCore+Lifecycle.swift).
    let functions: CoreFunctions

    /// Loads `<name>.framework` from the private frameworks folder of `bundle`.
    public init(named name: String, in bundle: Bundle = .main) throws(LibretroError) {
        guard let frameworksURL = bundle.privateFrameworksURL else {
            throw .frameworkNotFound(name: name, path: bundle.bundleURL.path(percentEncoded: false))
        }
        let frameworkURL = frameworksURL.appending(path: "\(name).framework", directoryHint: .isDirectory)
        guard let executableURL = Bundle(url: frameworkURL)?.executableURL else {
            throw .frameworkNotFound(name: name, path: frameworkURL.path(percentEncoded: false))
        }

        // RTLD_LOCAL keeps the core's retro_* symbols out of the global namespace,
        // so a second core with the same symbol names cannot bind to this one.
        let handle = executableURL.withUnsafeFileSystemRepresentation { path in
            dlopen(path, RTLD_NOW | RTLD_LOCAL)
        }
        guard let handle else {
            throw .loadFailed(name: name, reason: Self.dynamicLoaderError())
        }

        let apiVersion: @convention(c) () -> CUnsignedInt
        let getSystemInfo: @convention(c) (UnsafeMutablePointer<retro_system_info>?) -> Void
        let functions: CoreFunctions
        do throws(LibretroError) {
            apiVersion = try Self.function("retro_api_version", in: handle, core: name)
            getSystemInfo = try Self.function("retro_get_system_info", in: handle, core: name)
            functions = try CoreFunctions(handle: handle, core: name)
        } catch {
            dlclose(handle)
            throw error
        }
        self.name = name
        self.handle = handle
        retroAPIVersion = apiVersion
        retroGetSystemInfo = getSystemInfo
        self.functions = functions
    }

    deinit {
        dlclose(handle)
    }

    /// The libretro API version the core was built for (`retro_api_version`).
    public func apiVersion() -> UInt32 {
        UInt32(retroAPIVersion())
    }

    /// Static information about the core (`retro_get_system_info`).
    ///
    /// Libretro allows this call before `retro_init`, so it needs no running core.
    public func systemInfo() -> SystemInfo {
        var info = retro_system_info()
        retroGetSystemInfo(&info)
        return SystemInfo(info)
    }

    /// The names of the core frameworks in `bundle`, sorted.
    ///
    /// Libretro cores are named `<core>_libretro` by convention. Other frameworks
    /// in the bundle, for example graphics libraries a core needs, are ignored.
    public static func embeddedCoreNames(in bundle: Bundle = .main) -> [String] {
        guard let frameworksURL = bundle.privateFrameworksURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: frameworksURL, includingPropertiesForKeys: nil)
        else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "framework" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.hasSuffix("_libretro") }
            .sorted()
    }

    static func function<Function>(
        _ symbol: String, in handle: UnsafeMutableRawPointer, core name: String
    ) throws(LibretroError) -> Function {
        guard let address = dlsym(handle, symbol) else {
            throw .symbolNotFound(name: name, symbol: symbol, reason: dynamicLoaderError())
        }
        return unsafeBitCast(address, to: Function.self)
    }

    private static func dynamicLoaderError() -> String {
        guard let message = dlerror() else { return "unknown error" }
        return String(cString: message)
    }
}

// Not Sendable on purpose: a core keeps global state and is not thread-safe, so
// it stays in the isolation domain that loaded it: an EmulationSession creates
// it on its emulation thread and never lets it leave. Being noncopyable, the
// value has exactly one owner, and the handle is closed exactly once.
@available(*, unavailable)
extension LibretroCore: Sendable {}
