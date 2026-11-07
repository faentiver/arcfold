// Renderer shows what a core produces (docs/PLAN.md, section 5; ADR 0005):
// FrameMailbox and GameScreen for the picture, AudioRing and AudioOutput for
// the sound. Software cores only in M1; GPU cores (PSP) follow in M3.

import LibretroKit
import Synchronization

/// Hands pictures from the emulation thread to the screen without tearing,
/// locks or allocations.
///
/// The emulation thread (`VideoSink`) copies each picture into a free slot;
/// the display link takes the newest frame whose nominal time is due. When no
/// slot is free, the oldest unshown frame is overwritten. All slots are
/// allocated once in `init`. One producer and one consumer.
public final class FrameMailbox: VideoSink, @unchecked Sendable {
    // @unchecked: the pixel memory is shared raw memory. Each slot belongs to
    // exactly one side at a time, and ownership only moves through the slot's
    // atomic state word with acquire and release ordering:
    //   free -> writing -> ready   (producer)
    //   ready -> reading -> free   (consumer)
    //   ready -> free              (consumer drops an older frame)
    //   ready -> writing           (producer overwrites the oldest unshown frame)
    // A state word is `generation << 2 | phase`. The generation counts published
    // frames, so a compare-exchange on a ready slot fails if the producer took
    // it back and published a newer frame in the meantime.

    /// The pixel format of every picture in this mailbox.
    package let format: PixelFormat
    /// The size each slot holds.
    package let maxWidth: Int
    package let maxHeight: Int
    package let slotCount: Int

    private let slotBytes: Int
    private let storage: UnsafeMutableRawPointer
    private let states: UnsafeMutablePointer<Atomic<UInt64>>
    private let nominalTimes: UnsafeMutablePointer<Atomic<UInt64>>
    private let sequences: UnsafeMutablePointer<Atomic<UInt64>>
    /// Width in the upper and height in the lower 32 bits.
    private let sizes: UnsafeMutablePointer<Atomic<UInt64>>

    // Producer side.
    private let generation = Atomic<UInt64>(0)
    private let published = Atomic<UInt64>(0)
    private let overwritten = Atomic<UInt64>(0)
    private let lastSequence = Atomic<UInt64>(0)
    private let lastNominalTime = Atomic<UInt64>(0)
    /// Nominal time between two consecutive frames, for spotting late frames.
    private let framePeriod = Atomic<UInt64>(0)

    /// - Parameters:
    ///   - geometry: Slots are sized for `maxWidth x maxHeight`.
    ///   - format: The pixel format of the session; RGB565 and XRGB8888.
    ///   - slotCount: At least 3; 4 leaves room for a frame in flight to the GPU.
    public init(geometry: VideoGeometry, format: PixelFormat, slotCount: Int = 4) {
        precondition(slotCount >= 3, "A FrameMailbox needs at least 3 slots")
        precondition(format != .rgb1555, "Arcfold shows RGB565 and XRGB8888 only")
        precondition(geometry.maxWidth > 0 && geometry.maxHeight > 0, "The geometry has no size")
        self.format = format
        maxWidth = geometry.maxWidth
        maxHeight = geometry.maxHeight
        self.slotCount = slotCount
        slotBytes = geometry.maxWidth * geometry.maxHeight * format.bytesPerPixel

        storage = .allocate(byteCount: slotCount * slotBytes, alignment: 64)
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: slotCount * slotBytes)
        states = Self.makeAtomics(slotCount)
        nominalTimes = Self.makeAtomics(slotCount)
        sequences = Self.makeAtomics(slotCount)
        sizes = Self.makeAtomics(slotCount)
    }

    deinit {
        for atomics in [states, nominalTimes, sequences, sizes] {
            atomics.deinitialize(count: slotCount)
            atomics.deallocate()
        }
        storage.deallocate()
    }

    private static func makeAtomics(_ count: Int) -> UnsafeMutablePointer<Atomic<UInt64>> {
        let atomics = UnsafeMutablePointer<Atomic<UInt64>>.allocate(capacity: count)
        for index in 0..<count {
            (atomics + index).initialize(to: Atomic(0))
        }
        return atomics
    }

    // MARK: Producer

    /// Called on the emulation thread. Copies the visible rows into a slot,
    /// without the padding of the core's pitch, and publishes it. Pictures in
    /// another format than the mailbox's are dropped; a picture larger than
    /// the geometry is cut to it.
    public func submit(pixels: RawSpan, width: Int, height: Int, bytesPerRow: Int,
                       format: PixelFormat, stamp: FrameStamp) {
        guard format == self.format, width > 0, height > 0 else { return }
        let bytesPerPixel = format.bytesPerPixel
        let columns = min(width, maxWidth)
        let rows = min(height, maxHeight)
        let rowBytes = columns * bytesPerPixel
        guard bytesPerRow >= rowBytes, pixels.byteCount >= (rows - 1) * bytesPerRow + rowBytes else { return }

        let slot = acquireSlotForWriting()
        let destination = storage + slot * slotBytes
        pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            if bytesPerRow == rowBytes {
                destination.copyMemory(from: base, byteCount: rowBytes * rows)
            } else {
                for row in 0..<rows {
                    (destination + row * rowBytes).copyMemory(from: base + row * bytesPerRow, byteCount: rowBytes)
                }
            }
        }
        nominalTimes[slot].store(stamp.nominalTime, ordering: .relaxed)
        sequences[slot].store(stamp.sequence, ordering: .relaxed)
        sizes[slot].store(UInt64(columns) << 32 | UInt64(rows), ordering: .relaxed)

        let previousNominal = lastNominalTime.load(ordering: .relaxed)
        if stamp.sequence == lastSequence.load(ordering: .relaxed) &+ 1, stamp.nominalTime > previousNominal {
            framePeriod.store(stamp.nominalTime - previousNominal, ordering: .relaxed)
        }
        lastSequence.store(stamp.sequence, ordering: .relaxed)
        lastNominalTime.store(stamp.nominalTime, ordering: .relaxed)

        // Release: pixels and metadata become visible together with the state.
        let frameGeneration = generation.wrappingAdd(1, ordering: .relaxed).newValue
        states[slot].store(frameGeneration << 2 | Phase.ready, ordering: .releasing)
        published.wrappingAdd(1, ordering: .relaxed)
    }

    /// A free slot, or else the oldest ready one. With at least three slots and
    /// a consumer that holds at most one, one of them always exists.
    private func acquireSlotForWriting() -> Int {
        while true {
            var oldestReady: (index: Int, word: UInt64)?
            for index in 0..<slotCount {
                let word = states[index].load(ordering: .relaxed)
                switch word & Phase.mask {
                case Phase.free:
                    // Acquire: the consumer's reads of this slot happened before.
                    if states[index].compareExchange(
                        expected: word, desired: word & ~Phase.mask | Phase.writing, ordering: .acquiring
                    ).exchanged {
                        return index
                    }
                case Phase.ready:
                    // Same phase bits, so the smaller word is the older frame.
                    if oldestReady.map({ word < $0.word }) ?? true {
                        oldestReady = (index, word)
                    }
                default:
                    break
                }
            }
            if let oldestReady, states[oldestReady.index].compareExchange(
                expected: oldestReady.word, desired: oldestReady.word & ~Phase.mask | Phase.writing,
                ordering: .acquiring
            ).exchanged {
                overwritten.wrappingAdd(1, ordering: .relaxed)
                return oldestReady.index
            }
        }
    }

    /// Producer-side counters, read atomically.
    public var counters: MailboxCounters {
        MailboxCounters(
            published: published.load(ordering: .relaxed),
            overwritten: overwritten.load(ordering: .relaxed)
        )
    }

    // MARK: Consumer

    /// Takes the newest ready frame with `nominalTime + latency <= presentationTime`
    /// and drops the older ready ones. The frame stays reserved until `release`.
    /// Call `release` before the next `takeFrame`.
    ///
    /// - Parameters:
    ///   - presentationTime: When the picture will be on screen, in host time units.
    ///   - latency: The lead of the display link plus a reserve, in host time units.
    package func takeFrame(presentationTime: UInt64, latency: UInt64) -> MailboxSelection {
        guard presentationTime >= latency else { return .none }
        let deadline = presentationTime - latency
        for _ in 0..<(4 * slotCount) {
            var chosen: (index: Int, word: UInt64)?
            var newestReady: UInt64 = 0
            for index in 0..<slotCount {
                let word = states[index].load(ordering: .acquiring)
                guard word & Phase.mask == Phase.ready else { continue }
                newestReady = max(newestReady, word)
                if nominalTimes[index].load(ordering: .relaxed) <= deadline,
                   chosen.map({ word > $0.word }) ?? true {
                    chosen = (index, word)
                }
            }
            guard let chosen else { return .none }
            guard states[chosen.index].compareExchange(
                expected: chosen.word, desired: chosen.word & ~Phase.mask | Phase.reading,
                ordering: .acquiringAndReleasing
            ).exchanged else {
                // The producer took the slot back for a newer frame; look again.
                continue
            }

            var skipped = 0
            for index in 0..<slotCount where index != chosen.index {
                let word = states[index].load(ordering: .relaxed)
                if word & Phase.mask == Phase.ready, word < chosen.word, states[index].compareExchange(
                    expected: word, desired: word & ~Phase.mask | Phase.free, ordering: .releasing
                ).exchanged {
                    skipped += 1
                }
            }

            // The slot is ours now; its metadata no longer changes.
            let nominalTime = nominalTimes[chosen.index].load(ordering: .relaxed)
            let size = sizes[chosen.index].load(ordering: .relaxed)
            let width = Int(size >> 32)
            // Late: nothing newer is ready, although by the frame period the
            // next frame was due before this presentation.
            let period = framePeriod.load(ordering: .relaxed)
            let isLate = newestReady <= chosen.word && period > 0 && deadline >= period
                && nominalTime <= deadline - period
            let frame = MailboxFrame(
                slot: chosen.index,
                generation: chosen.word >> 2,
                pixels: UnsafeRawPointer(storage + chosen.index * slotBytes),
                width: width,
                height: Int(size & 0xFFFF_FFFF),
                bytesPerRow: width * format.bytesPerPixel,
                sequence: sequences[chosen.index].load(ordering: .relaxed),
                nominalTime: nominalTime
            )
            return .frame(frame, skipped: skipped, isLate: isLate)
        }
        return .none
    }

    /// Gives the slot of a taken frame back to the producer. Release: the
    /// consumer's reads of the pixels happen before the producer writes again.
    package func release(_ frame: MailboxFrame) {
        states[frame.slot].store(frame.generation << 2 | Phase.free, ordering: .releasing)
    }

    private enum Phase {
        static let mask: UInt64 = 0b11
        static let free: UInt64 = 0
        static let writing: UInt64 = 1
        static let ready: UInt64 = 2
        static let reading: UInt64 = 3
    }
}

/// A frame the consumer holds between `takeFrame` and `release`. The pixels
/// are compact rows of `bytesPerRow`, valid until the release.
package struct MailboxFrame {
    package let slot: Int
    package let generation: UInt64
    package let pixels: UnsafeRawPointer
    package let width: Int
    package let height: Int
    package let bytesPerRow: Int
    package let sequence: UInt64
    package let nominalTime: UInt64
}

/// What `FrameMailbox.takeFrame` found.
package enum MailboxSelection {
    /// No ready frame is due yet; keep showing the previous one.
    case none
    /// The frame to show. `skipped` older ready frames were dropped unshown;
    /// `isLate` is true when a newer frame was due but not delivered yet.
    case frame(MailboxFrame, skipped: Int, isLate: Bool)
}

/// What happened to the pictures the emulation thread delivered.
public struct MailboxCounters: Sendable, Hashable {
    /// Pictures copied into the mailbox.
    public var published: UInt64
    /// Unshown pictures overwritten because no slot was free.
    public var overwritten: UInt64

    public init(published: UInt64, overwritten: UInt64) {
        self.published = published
        self.overwritten = overwritten
    }
}
