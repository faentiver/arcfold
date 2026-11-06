import Foundation
import OSLog

/// One folder per app launch, Documents/SpikeResults/<name>. Separate folders
/// keep the tests of a device session apart, and no file of an older launch
/// ends up next to a newer report.
struct ResultStore: Sendable {
    let name: String
    let folder: URL

    static let log = Logger(subsystem: "com.faentiver.arcfold.spike.jit", category: "results")

    /// `requestedName` comes from the launch argument `-resultsName`; without
    /// one the launch time names the folder.
    init(requestedName: String?) {
        let cleaned = String((requestedName ?? "").map { character in
            character.isASCII && (character.isLetter || character.isNumber || "-_.".contains(character))
                ? character : "-"
        })
        name = cleaned.isEmpty ? Self.launchTimestamp() : cleaned
        folder = URL.documentsDirectory
            .appending(path: "SpikeResults", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Writes probes.json. `pending` is a probe that has started but not
    /// returned: if the probe kills the app, the file still names it.
    func saveProbes(_ probes: [JITProbe], pending: String?) {
        var entries = probes.map { ProbeEntry(label: $0.label, result: $0.passed ? "OK" : "FEHLER", detail: $0.detail) }
        if let pending {
            entries.append(ProbeEntry(label: pending, result: "läuft",
                                      detail: "Bleibt dieser Eintrag stehen, endete die App während dieser Probe."))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            save(data, as: "probes.json")
        }
    }

    func save(_ data: Data, as fileName: String) {
        do {
            try data.write(to: folder.appending(path: fileName), options: .atomic)
        } catch {
            Self.log.error("writing \(fileName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func launchTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

private struct ProbeEntry: Encodable {
    let label: String
    let result: String
    let detail: String
}
