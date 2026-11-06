import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SpikeModel {
    private(set) var title = "PSP GPU spike"
    private(set) var report = "Starting…"
    private(set) var lastImage: UIImage?
    private var started = false

    func startIfNeeded() {
        guard !started else { return }
        started = true

        let defaults = UserDefaults.standard
        let backend = Self.backend(named: defaults.string(forKey: "backend") ?? "gles")
        let frames = max(defaults.integer(forKey: "frames"), 0)
        let scale = max(defaults.integer(forKey: "scale"), 1)
        let captures = (defaults.string(forKey: "capture") ?? "60,300")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let exitWhenDone = defaults.bool(forKey: "exitWhenDone")
        let waitForGPU = defaults.bool(forKey: "waitForGPU")
        let cycles = max(defaults.integer(forKey: "cycles"), 1)
        let closesLibrary = defaults.bool(forKey: "dlclose")

        // The core writes next to the content, so it runs from a writable
        // folder, as imported games will on the device.
        let documents = URL.documentsDirectory
        let content = documents.appending(path: "content/gu-test.elf")
        do {
            try Self.copyContent(to: content)
        } catch {
            report = "Cannot prepare the content: \(error.localizedDescription)"
            return
        }
        let output = documents.appending(path: Self.name(of: backend), directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        title = "PSP GPU spike – \(Self.name(of: backend))"
        let configuration = SpikeConfiguration(
            backend: backend,
            frameCount: frames == 0 ? 600 : frames,
            renderScale: scale,
            captureFrames: captures.map { NSNumber(value: $0) },
            contentURL: content,
            outputDirectory: output,
            waitForGPUEachFrame: waitForGPU,
            cycles: cycles,
            closesLibrary: closesLibrary
        )
        SpikeHost(configuration: configuration).start { [weak self] result in
            self?.finish(result, output: output, exitWhenDone: exitWhenDone)
        }
    }

    private func finish(_ result: SpikeResult, output: URL, exitWhenDone: Bool) {
        report = result.report
        if let last = result.capturedImages.last {
            lastImage = UIImage(contentsOfFile: last.path(percentEncoded: false))
        }
        try? result.report.write(
            to: output.appending(path: "report.txt"), atomically: true, encoding: .utf8)
        if exitWhenDone {
            exit(result.succeeded ? 0 : 1)
        }
    }

    private static func copyContent(to destination: URL) throws {
        guard let source = Bundle.main.url(forResource: "gu-test", withExtension: "elf") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "gu-test.elf"])
        }
        let files = FileManager.default
        try files.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: destination.path(percentEncoded: false)) {
            try files.removeItem(at: destination)
        }
        try files.copyItem(at: source, to: destination)
    }

    private static func backend(named name: String) -> SpikeBackend {
        switch name {
        case "vulkan": .vulkan
        case "software": .software
        default: .openGLES
        }
    }

    private static func name(of backend: SpikeBackend) -> String {
        switch backend {
        case .openGLES: "gles"
        case .vulkan: "vulkan"
        case .software: "software"
        @unknown default: "unknown"
        }
    }
}
