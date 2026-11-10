import Dispatch
import Foundation
import Synchronization

// The battery save of a session (ADR 0005, section 8): read into the core
// before the first frame, compared every 30 frames and written atomically on a
// serial utility queue, and at once when the session pauses, saves or stops.

/// The files of a battery save: `battery.sav`, its previous version
/// `battery.sav.bak` and, while a write is in progress, `battery.sav.tmp`.
enum BatterySaveFile {
    /// The previous version, kept by every write.
    static func backupURL(of url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".bak")
    }

    /// The file a write goes to before it replaces `url`.
    static func temporaryURL(of url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".tmp")
    }

    /// Removes a temporary file that an interrupted write left behind.
    static func removeLeftovers(of url: URL) {
        try? FileManager.default.removeItem(at: temporaryURL(of: url))
    }

    /// The contents to load: the main file, unless it is missing, unreadable,
    /// empty or shorter than the backup, which points to a damaged file; then
    /// the backup. Nil if there is neither. A main file shorter than the core's
    /// memory is normal: mGBA reports 128 KiB until it knows the save type.
    static func read(_ url: URL) throws(SessionError) -> Data? {
        let main = readIfPresent(url)
        let backup = readIfPresent(backupURL(of: url))
        switch (main, backup) {
        case let (.success(main?), .success(backup?)):
            return main.isEmpty || main.count < backup.count ? backup : main
        case let (.success(main?), _):
            return main
        case let (_, .success(backup?)):
            return backup
        case (.success(nil), .success(nil)):
            return nil
        case let (.failure(error), _), let (_, .failure(error)):
            throw error
        }
    }

    /// Writes `bytes` to `url` atomically: a temporary file in the same folder,
    /// flushed to storage, then swapped in with `replaceItemAt`, which keeps the
    /// previous file as `battery.sav.bak`. On failure the old file is intact.
    static func write(_ bytes: UnsafeRawBufferPointer, to url: URL) throws(SessionError) {
        let temporary = temporaryURL(of: url)
        do {
            // Default data protection on purpose: with `.complete` the write
            // would fail while the device is locked.
            guard FileManager.default.createFile(atPath: temporary.path(percentEncoded: false), contents: nil) else {
                throw SessionError.batterySave(reason: "Cannot create \(temporary.lastPathComponent)")
            }
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.write(contentsOf: bytes)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            _ = try FileManager.default.replaceItemAt(
                url, withItemAt: temporary,
                backupItemName: backupURL(of: url).lastPathComponent,
                options: .withoutDeletingBackupItem
            )
        } catch let error as SessionError {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw .batterySave(reason: error.localizedDescription)
        }
    }

    private static func readIfPresent(_ url: URL) -> Result<Data?, SessionError> {
        do {
            return .success(try Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .success(nil)
        } catch {
            return .failure(.batterySave(reason: error.localizedDescription))
        }
    }
}

/// Writes battery saves on a serial queue with QoS `.utility`.
///
/// The emulation thread copies a save into one of two buffers allocated once
/// and hands it over; the queue writes it and frees the buffer again. If both
/// buffers are still in flight, a periodic save waits for the next check.
/// Each buffer comes with a work item created once, so a handover allocates
/// nothing on the emulation thread. `@unchecked Sendable`: a buffer belongs to
/// the emulation thread while its `isBusy` flag is clear and to the queue
/// while it is set.
final class BatterySaveWriter: @unchecked Sendable {
    private final class Slot: @unchecked Sendable {
        let isBusy = Atomic<Bool>(false)
        var buffer: UnsafeMutableRawBufferPointer
        var count = 0
        /// Runs on the queue after this write; set only for immediate saves.
        var completion: (@Sendable (Result<Void, SessionError>) -> Void)?
        /// Submitted for every write of this slot. A dispatch block may run
        /// any number of times as long as nobody waits on it (dispatch/block.h).
        var work: DispatchWorkItem?

        init(capacity: Int) {
            buffer = .allocate(byteCount: max(capacity, 1), alignment: 16)
        }

        deinit {
            buffer.deallocate()
        }
    }

    private let url: URL
    private let events: AsyncStream<SessionEvent>.Continuation
    private let queue = DispatchQueue(label: "com.faentiver.arcfold.battery-save", qos: .utility)
    // Two named slots rather than an array: no collection access on the emulation thread.
    private let firstSlot: Slot
    private let secondSlot: Slot

    /// - Parameter capacity: The size of the save memory; buffers grow if a
    ///   core later reports more.
    init(url: URL, capacity: Int, events: AsyncStream<SessionEvent>.Continuation) {
        self.url = url
        self.events = events
        firstSlot = Slot(capacity: capacity)
        secondSlot = Slot(capacity: capacity)
        for slot in [firstSlot, secondSlot] {
            slot.work = DispatchWorkItem { [weak self, unowned slot] in
                self?.writeFile(of: slot)
            }
        }
    }

    /// Emulation thread: copies `save` into a free buffer and queues the write.
    /// Returns false, without copying, if both buffers are in flight and
    /// `waitForBuffer` is false. `completion` runs on the queue after the write.
    @discardableResult
    func write(
        _ save: UnsafeRawBufferPointer, waitForBuffer: Bool,
        completion: (@Sendable (Result<Void, SessionError>) -> Void)? = nil
    ) -> Bool {
        var slot = freeSlot()
        if slot == nil, waitForBuffer {
            waitUntilIdle()
            slot = freeSlot()
        }
        guard let slot, let work = slot.work else { return false }
        if slot.buffer.count < save.count {
            slot.buffer.deallocate()
            slot.buffer = .allocate(byteCount: save.count, alignment: 16)
        }
        slot.buffer.copyMemory(from: save)
        slot.count = save.count
        slot.completion = completion
        slot.isBusy.store(true, ordering: .relaxed)
        // The queue takes the work item after these stores, so it sees them.
        queue.async(execute: work)
        return true
    }

    /// Runs `completion` on the queue once every write handed over before has finished.
    func afterPendingWrites(_ completion: @escaping @Sendable () -> Void) {
        queue.async(execute: completion)
    }

    /// Blocks until every write handed over before has finished.
    func waitUntilIdle() {
        queue.sync {}
    }

    private func freeSlot() -> Slot? {
        if !firstSlot.isBusy.load(ordering: .acquiring) {
            return firstSlot
        }
        if !secondSlot.isBusy.load(ordering: .acquiring) {
            return secondSlot
        }
        return nil
    }

    /// The queue: writes the slot, reports the result and frees the slot.
    private func writeFile(of slot: Slot) {
        let result: Result<Void, SessionError>
        do throws(SessionError) {
            try BatterySaveFile.write(UnsafeRawBufferPointer(rebasing: slot.buffer[..<slot.count]), to: url)
            result = .success(())
            events.yield(.batterySaveWritten(bytes: slot.count))
        } catch {
            result = .failure(error)
            events.yield(.batterySaveFailed(reason: error.description))
        }
        let completion = slot.completion
        slot.completion = nil
        // From here on the emulation thread may fill the slot again.
        slot.isBusy.store(false, ordering: .releasing)
        completion?(result)
    }
}

/// The battery save as the emulation thread sees it: loads the file into the
/// core, notices changes and decides when to write. Emulation thread only.
final class BatterySaveMonitor {
    /// Frames between two comparisons; at about 60 frames per second twice a second.
    static let checkInterval: UInt64 = 30

    let url: URL
    private let writer: BatterySaveWriter
    /// The contents at the last comparison, allocated once.
    private var lastSeen: UnsafeMutableRawBufferPointer
    private var lastSeenCount = 0
    /// The contents differ from what was last handed to the writer.
    private var isDirty = false
    /// A save file exists or is on its way. Until then a memory that holds only
    /// 0xFF is never written, so games without saves leave no file.
    private var fileExists = false

    init(url: URL, capacity: Int, events: AsyncStream<SessionEvent>.Continuation) {
        self.url = url
        writer = BatterySaveWriter(url: url, capacity: capacity, events: events)
        lastSeen = .allocate(byteCount: max(capacity, 1), alignment: 16)
    }

    deinit {
        lastSeen.deallocate()
    }

    /// Before the first frame: removes a leftover temporary file and copies the
    /// save, or its backup, into `memory`, at most `memory.count` bytes.
    /// `blankByte`, if given, fills what no file covers: the whole memory
    /// without a file, the rest behind a shorter one, for example after a new
    /// core version gave a game a larger save (blank EEPROM and flash read
    /// 0xFF; ADR 0006, section 11). Without it the rest keeps what the core
    /// put there (0xFF for mGBA, whose memory is larger than its save until it
    /// knows the save type).
    func load(into memory: UnsafeMutableRawBufferPointer?, blankByte: UInt8? = nil) throws(SessionError) {
        BatterySaveFile.removeLeftovers(of: url)
        let data = try BatterySaveFile.read(url)
        fileExists = data != nil
        guard let memory else { return }
        var count = 0
        if let data {
            count = min(data.count, memory.count)
            data.withUnsafeBytes { bytes in
                memory.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[..<count]))
            }
        }
        if let blankByte, let base = memory.baseAddress, count < memory.count {
            memset(base + count, Int32(blankByte), memory.count - count)
        }
        remember(UnsafeRawBufferPointer(memory))
        isDirty = false
    }

    /// Every `checkInterval` frames: writes when the memory changed since the
    /// last write but not since the previous check. Games often write a save
    /// over several frames; a copy in the middle would be inconsistent.
    func check(_ memory: UnsafeRawBufferPointer?) {
        guard let memory else { return }
        if hasChanged(memory) {
            remember(memory)
            isDirty = true
        } else if isDirty {
            handOver(waitForBuffer: false, completion: nil)
        }
    }

    /// For pause, `saveBatteryNow()` and stop: writes a changed save without
    /// waiting for it to settle. `completion` runs once it is on disk, or at
    /// once after pending writes if nothing changed.
    func saveNow(_ memory: UnsafeRawBufferPointer?, completion: @escaping @Sendable (Result<Void, SessionError>) -> Void) {
        if let memory, hasChanged(memory) {
            remember(memory)
            isDirty = true
        }
        if !isDirty || !handOver(waitForBuffer: true, completion: completion) {
            writer.afterPendingWrites { completion(.success(())) }
        }
    }

    /// Blocks until every handed-over save is on disk.
    func waitUntilWritten() {
        writer.waitUntilIdle()
    }

    /// Hands the remembered contents to the writer. Returns false if nothing
    /// was handed over.
    @discardableResult
    private func handOver(
        waitForBuffer: Bool, completion: (@Sendable (Result<Void, SessionError>) -> Void)?
    ) -> Bool {
        let contents = UnsafeRawBufferPointer(rebasing: lastSeen[..<lastSeenCount])
        if !fileExists, contents.allSatisfy({ $0 == 0xFF }) {
            isDirty = false
            return false
        }
        guard writer.write(contents, waitForBuffer: waitForBuffer, completion: completion) else {
            return false
        }
        fileExists = true
        isDirty = false
        return true
    }

    /// Whether `memory` differs from the remembered contents. A memory that
    /// shrank counts as unchanged if what is left is the same: mGBA reports
    /// 128 KiB until it detects the save type, then the real size.
    private func hasChanged(_ memory: UnsafeRawBufferPointer) -> Bool {
        guard memory.count <= lastSeenCount, let base = memory.baseAddress, let seen = lastSeen.baseAddress else {
            return true
        }
        if memcmp(base, seen, memory.count) != 0 {
            return true
        }
        lastSeenCount = memory.count
        return false
    }

    private func remember(_ memory: UnsafeRawBufferPointer) {
        if lastSeen.count < memory.count {
            lastSeen.deallocate()
            lastSeen = .allocate(byteCount: memory.count, alignment: 16)
        }
        lastSeen.copyMemory(from: memory)
        lastSeenCount = memory.count
    }
}
