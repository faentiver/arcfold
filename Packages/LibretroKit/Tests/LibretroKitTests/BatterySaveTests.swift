import Foundation
@testable import LibretroKit
import Testing

/// The file logic of the battery save in a temporary folder (ADR 0005,
/// section 8): atomic writes with a backup, the fallback to the backup, the
/// rule for memories that hold only 0xFF and memories of different sizes.
struct BatterySaveTests {
    // MARK: Files

    @Test func writesAreAtomicAndKeepThePreviousVersion() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")

        try write([1, 2, 3], to: url)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(!folder.contains("battery.sav.bak"))

        try write([4, 5, 6, 7], to: url)
        #expect(try Data(contentsOf: url) == Data([4, 5, 6, 7]))
        #expect(try Data(contentsOf: BatterySaveFile.backupURL(of: url)) == Data([1, 2, 3]))

        try write([8], to: url)
        #expect(try Data(contentsOf: url) == Data([8]))
        #expect(try Data(contentsOf: BatterySaveFile.backupURL(of: url)) == Data([4, 5, 6, 7]))
        #expect(folder.files == ["battery.sav", "battery.sav.bak"])
    }

    @Test func readPrefersTheMainFile() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        #expect(try BatterySaveFile.read(url) == nil)

        try Data([9, 9, 9, 9]).write(to: BatterySaveFile.backupURL(of: url))
        // Only the backup: an interrupted replacement.
        #expect(try BatterySaveFile.read(url) == Data([9, 9, 9, 9]))

        try Data([1, 2, 3, 4]).write(to: url)
        #expect(try BatterySaveFile.read(url) == Data([1, 2, 3, 4]))
    }

    @Test func aDamagedMainFileFallsBackToTheBackup() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        try Data(repeating: 7, count: 32_768).write(to: BatterySaveFile.backupURL(of: url))

        // Shorter than the backup: cut off.
        try Data(repeating: 1, count: 1_000).write(to: url)
        #expect(try BatterySaveFile.read(url)?.count == 32_768)
        // Empty.
        try Data().write(to: url)
        #expect(try BatterySaveFile.read(url)?.first == 7)
    }

    @Test func anUnreadableMainFileFallsBackToTheBackup() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        try Data(repeating: 7, count: 32_768).write(to: BatterySaveFile.backupURL(of: url))
        // Unreadable: here a folder where the file belongs.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(try BatterySaveFile.read(url)?.first == 7)
        // Without a backup the error is reported.
        try FileManager.default.removeItem(at: BatterySaveFile.backupURL(of: url))
        #expect(throws: SessionError.self) {
            try BatterySaveFile.read(url)
        }
    }

    // MARK: Monitor

    @Test func loadCopiesAtMostTheMemoryAndRemovesALeftoverTemporaryFile() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        // The real save of a GBA game with SRAM, 32 KiB.
        try Data(repeating: 0x41, count: 32_768).write(to: url)
        try Data([1, 2, 3]).write(to: BatterySaveFile.temporaryURL(of: url))
        // mGBA reports 128 KiB of 0xFF until it knows the save type.
        let memory = Memory(count: 131_072)
        let (monitor, _) = makeMonitor(url: url, capacity: memory.count)

        try monitor.load(into: memory.buffer)

        #expect(memory.bytes(0..<32_768).allSatisfy { $0 == 0x41 })
        #expect(memory.bytes(32_768..<131_072).allSatisfy { $0 == 0xFF })
        #expect(!folder.contains("battery.sav.tmp"))

        // A file longer than the memory fills only the memory.
        let small = Memory(count: 16)
        let (smallMonitor, _) = makeMonitor(url: url, capacity: small.count)
        try smallMonitor.load(into: small.buffer)
        #expect(small.bytes(0..<16).allSatisfy { $0 == 0x41 })
    }

    @Test func aMemoryWithOnlyFFIsNeverWrittenWhileNoFileExists() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        let memory = Memory(count: 131_072)
        let (monitor, _) = makeMonitor(url: url, capacity: memory.count)
        try monitor.load(into: memory.buffer)

        for _ in 0..<3 {
            monitor.check(memory.readOnly)
        }
        let result = await saveNow(monitor, memory)
        monitor.waitUntilWritten()

        #expect(result.isSuccess)
        #expect(folder.files.isEmpty)
    }

    @Test func aChangeIsWrittenOnceItHasNotChangedForOneCheck() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        let memory = Memory(count: 32_768)
        let (monitor, events) = makeMonitor(url: url, capacity: memory.count)
        try monitor.load(into: memory.buffer)

        memory.write(Array("ARCF".utf8) + [1])
        monitor.check(memory.readOnly)
        monitor.waitUntilWritten()
        // Changed since the previous check: the game may still be writing.
        #expect(!folder.contains("battery.sav"))

        monitor.check(memory.readOnly)
        monitor.waitUntilWritten()
        #expect(try Data(contentsOf: url) == Data(memory.bytes(0..<32_768)))

        // Unchanged: nothing more is written.
        monitor.check(memory.readOnly)
        monitor.waitUntilWritten()
        #expect(!folder.contains("battery.sav.bak"))
        #expect(await events.firstEvents(1) == [.batterySaveWritten(bytes: 32_768)])
    }

    @Test func saveNowWritesAChangeWithoutWaitingForTheNextCheck() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        let memory = Memory(count: 512)
        let (monitor, _) = makeMonitor(url: url, capacity: memory.count)
        try monitor.load(into: memory.buffer)

        memory.write([0, 1, 2, 3])
        #expect(await saveNow(monitor, memory).isSuccess)
        // The completion runs once the file is on disk.
        #expect(try Data(contentsOf: url) == Data(memory.bytes(0..<512)))

        // Nothing changed since: no second write, no backup.
        #expect(await saveNow(monitor, memory).isSuccess)
        monitor.waitUntilWritten()
        #expect(!folder.contains("battery.sav.bak"))
    }

    @Test func aMemoryThatShrinksToTheSameContentsIsNoChange() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        try Data(repeating: 0x42, count: 32_768).write(to: url)
        let memory = Memory(count: 131_072)
        let (monitor, _) = makeMonitor(url: url, capacity: memory.count)
        try monitor.load(into: memory.buffer)

        // mGBA detected SRAM: the same memory now reports 32 KiB.
        let detected = UnsafeRawBufferPointer(rebasing: memory.readOnly[..<32_768])
        monitor.check(detected)
        monitor.check(detected)
        #expect(await saveNow(monitor, detected).isSuccess)
        monitor.waitUntilWritten()
        #expect(!folder.contains("battery.sav.bak"))

        // A real change is written at the new size.
        memory.write([0x43])
        monitor.check(detected)
        monitor.check(detected)
        monitor.waitUntilWritten()
        #expect(try Data(contentsOf: url).count == 32_768)
        #expect(try Data(contentsOf: url).first == 0x43)
    }

    @Test func onceAFileExistsAMemoryWithOnlyFFIsWritten() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        try Data(repeating: 0x10, count: 64).write(to: url)
        let memory = Memory(count: 64)
        let (monitor, _) = makeMonitor(url: url, capacity: memory.count)
        try monitor.load(into: memory.buffer)

        memory.write(Array(repeating: 0xFF, count: 64))
        #expect(await saveNow(monitor, memory).isSuccess)
        #expect(try Data(contentsOf: url) == Data(repeating: 0xFF, count: 64))
    }

    @Test func aFailedWriteIsReportedAndKeepsTheOldFile() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "battery.sav")
        try Data([1, 1]).write(to: url)
        let memory = Memory(count: 2)
        let (monitor, events) = makeMonitor(url: url, capacity: memory.count)
        try monitor.load(into: memory.buffer)
        // A folder where the temporary file belongs makes the write fail.
        try FileManager.default.createDirectory(at: BatterySaveFile.temporaryURL(of: url), withIntermediateDirectories: false)

        memory.write([2, 2])
        let result = await saveNow(monitor, memory)

        guard case .failure(.batterySave) = result else {
            Issue.record("Expected a battery save error, got \(result)")
            return
        }
        #expect(try Data(contentsOf: url) == Data([1, 1]))
        let event = await events.firstEvents(1).first
        guard case .batterySaveFailed = event else {
            Issue.record("Expected batterySaveFailed, got \(String(describing: event))")
            return
        }
    }

    // MARK: Helpers

    private func write(_ bytes: [UInt8], to url: URL) throws {
        try bytes.withUnsafeBytes { buffer in
            try BatterySaveFile.write(buffer, to: url)
        }
    }

    private func makeMonitor(url: URL, capacity: Int) -> (BatterySaveMonitor, AsyncStream<SessionEvent>) {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        return (BatterySaveMonitor(url: url, capacity: capacity, events: continuation), stream)
    }

    private func saveNow(_ monitor: BatterySaveMonitor, _ memory: Memory) async -> Result<Void, SessionError> {
        await saveNow(monitor, memory.readOnly)
    }

    private func saveNow(_ monitor: BatterySaveMonitor, _ memory: UnsafeRawBufferPointer) async -> Result<Void, SessionError> {
        await withCheckedContinuation { continuation in
            monitor.saveNow(memory) { continuation.resume(returning: $0) }
        }
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}

extension AsyncStream<SessionEvent> {
    /// The first `count` events.
    func firstEvents(_ count: Int) async -> [SessionEvent] {
        var events: [SessionEvent] = []
        for await event in self {
            events.append(event)
            if events.count == count { break }
        }
        return events
    }
}

/// The save memory of a pretend core, 0xFF like mGBA's.
final class Memory {
    let buffer: UnsafeMutableRawBufferPointer

    init(count: Int) {
        buffer = .allocate(byteCount: count, alignment: 16)
        buffer.initializeMemory(as: UInt8.self, repeating: 0xFF)
    }

    deinit {
        buffer.deallocate()
    }

    var count: Int { buffer.count }
    var readOnly: UnsafeRawBufferPointer { UnsafeRawBufferPointer(buffer) }

    func bytes(_ range: Range<Int>) -> [UInt8] {
        Array(buffer[range])
    }

    /// Writes `bytes` at the start, as a game would.
    func write(_ bytes: [UInt8]) {
        for (index, byte) in bytes.enumerated() {
            buffer[index] = byte
        }
    }
}

/// A folder in the temporary directory, removed with the object.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LibretroKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var files: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted()
    }

    func contains(_ name: String) -> Bool {
        files.contains(name)
    }
}
