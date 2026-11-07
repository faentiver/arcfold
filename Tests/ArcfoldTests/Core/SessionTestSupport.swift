import CryptoKit
import Darwin
import Foundation
import LibretroKit
import Synchronization
import Testing

/// A folder for one test's battery save, system and save folders, removed afterwards.
final class SessionFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "ArcfoldCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var batterySave: URL {
        url.appending(path: "battery.sav")
    }

    /// The session for `selftest.gba` from the test bundle with mGBA from the app bundle.
    func configuration(
        pacing: Pacing = .unthrottled, coreName: String = "mgba_libretro", game: URL? = nil
    ) throws -> SessionConfiguration {
        SessionConfiguration(
            coreName: coreName,
            game: try game ?? Fixture.gbaSelftest.url(),
            batterySave: batterySave,
            systemDirectory: url.appending(path: "System", directoryHint: .isDirectory),
            saveDirectory: url,
            // As in the app (ADR 0005): never pick up a BIOS file.
            coreOptions: ["mgba_use_bios": "OFF"],
            pacing: pacing
        )
    }
}

/// Records the pictures a session delivers: stamps, arrival times and the
/// visible pixels of chosen frames.
final class PictureRecorder: VideoSink {
    struct Shape: Hashable {
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var format: PixelFormat
    }

    private struct State {
        var stamps: [FrameStamp] = []
        var arrivals: [UInt64] = []
        var shapes: Set<Shape> = []
        var pictures: [UInt64: SelftestPicture] = [:]
    }

    private let capturing: Set<UInt64>
    private let state = Mutex(State())

    /// - Parameter frames: The sequence numbers whose pixels to keep.
    init(capturing frames: Set<UInt64> = []) {
        capturing = frames
    }

    var count: Int { state.withLock { $0.stamps.count } }
    var stamps: [FrameStamp] { state.withLock { $0.stamps } }
    var arrivals: [UInt64] { state.withLock { $0.arrivals } }
    var shapes: Set<Shape> { state.withLock { $0.shapes } }

    func picture(_ frame: UInt64) -> SelftestPicture? {
        state.withLock { $0.pictures[frame] }
    }

    func submit(pixels: RawSpan, width: Int, height: Int, bytesPerRow: Int, format: PixelFormat, stamp: FrameStamp) {
        let arrival = mach_absolute_time()
        var picture: SelftestPicture?
        if capturing.contains(stamp.sequence) {
            let rowBytes = width * format.bytesPerPixel
            let visible = pixels.withUnsafeBytes { raw in
                var rows: [UInt8] = []
                rows.reserveCapacity(rowBytes * height)
                for row in 0..<height {
                    rows += raw[row * bytesPerRow ..< row * bytesPerRow + rowBytes]
                }
                return rows
            }
            picture = SelftestPicture(width: width, height: height, pixels: visible)
        }
        let shape = Shape(width: width, height: height, bytesPerRow: bytesPerRow, format: format)
        state.withLock { state in
            state.stamps.append(stamp)
            state.arrivals.append(arrival)
            state.shapes.insert(shape)
            if let picture {
                state.pictures[stamp.sequence] = picture
            }
        }
    }
}

/// Records every sample a session delivers, and how many frames each write had.
final class SoundRecorder: AudioSink {
    private struct State {
        var samples: [Int16] = []
        var writes: [Int] = []
    }

    private let state = Mutex(State())

    /// Interleaved stereo samples, left first.
    var samples: [Int16] { state.withLock { $0.samples } }
    /// Audio frames per write, in order.
    var writes: [Int] { state.withLock { $0.writes } }

    func write(_ samples: Span<Int16>) -> AudioBufferStatus {
        let copy = samples.withUnsafeBufferPointer { Array($0) }
        state.withLock { state in
            state.samples += copy
            state.writes.append(copy.count / 2)
        }
        // Like an output that is not playing yet: the clock stays nominal.
        return AudioBufferStatus(bufferedFrames: 0, targetFrames: 0, isConsuming: false)
    }
}

/// An audio sink that plays at `sampleRate` on the host clock once it has
/// buffered `targetFrames`, like an output after priming. It refills after it
/// ran dry.
final class ClockedSoundSink: AudioSink {
    private struct State {
        var level = 0.0
        var isPlaying = false
        var lastWrite: UInt64 = 0
        var underruns = 0
    }

    let sampleRate: Double
    let targetFrames: Int
    private let state = Mutex(State())
    private let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    init(sampleRate: Double, targetFrames: Int) {
        self.sampleRate = sampleRate
        self.targetFrames = targetFrames
    }

    var underruns: Int { state.withLock { $0.underruns } }

    func write(_ samples: Span<Int16>) -> AudioBufferStatus {
        let now = mach_absolute_time()
        let frames = samples.count / 2
        return state.withLock { state in
            if state.isPlaying {
                state.level -= Double(now - state.lastWrite) * secondsPerTick * sampleRate
                if state.level < 0 {
                    state.underruns += 1
                    state.level = 0
                    state.isPlaying = false
                }
            }
            state.lastWrite = now
            state.level += Double(frames)
            if !state.isPlaying, state.level >= Double(targetFrames) {
                state.isPlaying = true
            }
            return AudioBufferStatus(
                bufferedFrames: Int(state.level), targetFrames: targetFrames, isConsuming: state.isPlaying
            )
        }
    }
}

/// A picture of `selftest.gba`, RGB565 without row padding. The layout is
/// described in `Tests/Fixtures/gba/selftest/make_gba_selftest.py`.
struct SelftestPicture: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    /// SHA-256 of the visible pixels, row by row, as in `docs/adr/0005/selftest-mgba-macos.txt`.
    var sha256: String {
        SHA256.hash(data: Data(pixels)).map { String(format: "%02x", $0) }.joined()
    }

    /// The boot counter in SRAM: 1 after the first start.
    var bootCounter: Int { number(bits: 8, row: 116, spacing: 16) }
    /// Counts frames from the first vertical blank; frame number − 6 in mGBA.
    var frameCounter: Int { number(bits: 16, row: 128, spacing: 14) }
    /// KEYINPUT as the program read it, bit 0 is A.
    var keys: Int { number(bits: 10, row: 140, spacing: 16) }

    /// Reads a row of 8 × 8 blocks, most significant bit on the left. A block
    /// is unlit in BGR555 0x18C6, which mGBA turns into red 6, green 6, blue 6.
    private func number(bits: Int, row y: Int, spacing: Int) -> Int {
        var value = 0
        for bit in 0..<bits {
            let x = 8 + (bits - 1 - bit) * spacing
            let index = ((y + 4) * width + x + 4) * 2
            let pixel = UInt16(pixels[index]) | UInt16(pixels[index + 1]) << 8
            let isUnlit = (pixel >> 11) & 31 == 6 && (pixel >> 6) & 31 == 6 && pixel & 31 == 6
            if !isUnlit {
                value |= 1 << bit
            }
        }
        return value
    }
}

/// The frequency of a square wave in interleaved stereo samples, from the
/// rising crossings of the left channel through its mean.
func toneFrequency(of samples: ArraySlice<Int16>, sampleRate: Double) -> Double {
    let left = stride(from: samples.startIndex, to: samples.endIndex, by: 2).map { Double(samples[$0]) }
    guard left.count > 1 else { return 0 }
    let mean = left.reduce(0, +) / Double(left.count)
    var crossings = 0
    for index in 1..<left.count where left[index - 1] < mean && mean <= left[index] {
        crossings += 1
    }
    return Double(crossings) / (Double(left.count) / sampleRate)
}

/// Waits until `condition` holds, polling every 10 ms.
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw WaitTimedOut()
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

struct WaitTimedOut: Error {}

extension AsyncStream<SessionEvent> {
    /// All events until the stream finishes, which it does after `stop()`.
    func collect() async -> [SessionEvent] {
        var events: [SessionEvent] = []
        for await event in self {
            events.append(event)
        }
        return events
    }
}
