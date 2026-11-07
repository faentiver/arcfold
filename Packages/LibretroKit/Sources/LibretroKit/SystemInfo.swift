internal import CLibretro

/// Static information a core reports about itself (`struct retro_system_info`).
public struct SystemInfo: Hashable, Sendable {
    /// The name of the core, for example "mGBA".
    public let libraryName: String

    /// The version of the core, for example "0.10.5".
    public let libraryVersion: String

    /// File extensions the core loads, without dots, for example `["gba"]`.
    public let validExtensions: [String]

    /// The core reads content from a file path itself instead of from memory.
    public let needsFullPath: Bool

    /// The frontend must pass archives to the core without extracting them.
    public let blocksExtract: Bool

    /// For previews and tests; a running core reports its own values.
    public init(
        libraryName: String, libraryVersion: String, validExtensions: [String],
        needsFullPath: Bool, blocksExtract: Bool
    ) {
        self.libraryName = libraryName
        self.libraryVersion = libraryVersion
        self.validExtensions = validExtensions
        self.needsFullPath = needsFullPath
        self.blocksExtract = blocksExtract
    }
}

extension SystemInfo {
    /// Copies the strings, which belong to the core and live only as long as it is loaded.
    init(_ info: retro_system_info) {
        libraryName = info.library_name.map { String(cString: $0) } ?? ""
        libraryVersion = info.library_version.map { String(cString: $0) } ?? ""
        validExtensions = info.valid_extensions.map {
            String(cString: $0).split(separator: "|").map(String.init)
        } ?? []
        needsFullPath = info.need_fullpath
        blocksExtract = info.block_extract
    }
}
