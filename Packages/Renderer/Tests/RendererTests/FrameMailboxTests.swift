import Darwin
import Foundation
import LibretroKit
import Renderer
import Synchronization
import Testing

/// The picture handoff between the emulation thread and the display link
/// (ADR 0005, section 5).
struct FrameMailboxTests {
    static let geometry = VideoGeometry(baseWidth: 240, baseHeight: 160, maxWidth: 240, maxHeight: 160, aspectRatio: 1.5)

    /// A picture whose every pixel holds `value`, with mGBA's pitch of 512 bytes.
    static func picture(_ value: UInt16, width: Int = 240, height: Int = 160, pitchPixels: Int = 256) -> [UInt16] {
        [UInt16](repeating: value, count: pitchPixels * height)
    }

    static func submit(_ mailbox: FrameMailbox, value: UInt16, sequence: UInt64, nominalTime: UInt64) {
        let pixels = picture(value)
        mailbox.submit(pixels: pixels.span.bytes, width: 240, height: 160, bytesPerRow: 512, format: .rgb565,
                       stamp: FrameStamp(sequence: sequence, nominalTime: nominalTime))
    }

    /// Takes a frame and returns what the consumer saw, releasing the slot.
    static func take(_ mailbox: FrameMailbox, at time: UInt64, latency: UInt64 = 0)
        -> (sequence: UInt64, value: UInt16, skipped: Int, isLate: Bool)?
    {
        guard case let .frame(frame, skipped, isLate) = mailbox.takeFrame(presentationTime: time, latency: latency) else {
            return nil
        }
        defer { mailbox.release(frame) }
        let value = frame.pixels.load(as: UInt16.self)
        return (frame.sequence, value, skipped, isLate)
    }

    @Test func picksTheNewestDueFrameAndDropsOlderOnes() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565)
        Self.submit(mailbox, value: 1, sequence: 1, nominalTime: 100)
        Self.submit(mailbox, value: 2, sequence: 2, nominalTime: 200)
        Self.submit(mailbox, value: 3, sequence: 3, nominalTime: 300)

        #expect(Self.take(mailbox, at: 50) == nil, "Nothing is due before the first nominal time")

        let first = Self.take(mailbox, at: 250)
        #expect(first?.sequence == 2)
        #expect(first?.value == 2)
        #expect(first?.skipped == 1, "Frame 1 was due but older; it is dropped unshown")

        #expect(Self.take(mailbox, at: 260) == nil, "Frame 3 is not due yet and frame 2 was shown")
        #expect(Self.take(mailbox, at: 300)?.sequence == 3)
        #expect(mailbox.counters == MailboxCounters(published: 3, overwritten: 0))
    }

    @Test func latencyDelaysTheChoice() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565)
        Self.submit(mailbox, value: 7, sequence: 1, nominalTime: 1_000)
        #expect(Self.take(mailbox, at: 1_050, latency: 60) == nil)
        #expect(Self.take(mailbox, at: 1_060, latency: 60)?.sequence == 1)
        #expect(Self.take(mailbox, at: 10, latency: 60) == nil, "A presentation time below the latency selects nothing")
    }

    @Test func overwritesTheOldestUnshownFrameWhenNoSlotIsFree() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565, slotCount: 4)
        for sequence in 1...6 {
            Self.submit(mailbox, value: UInt16(sequence), sequence: UInt64(sequence), nominalTime: UInt64(sequence) * 100)
        }
        #expect(mailbox.counters == MailboxCounters(published: 6, overwritten: 2))

        let newest = Self.take(mailbox, at: 10_000)
        #expect(newest?.sequence == 6)
        #expect(newest?.value == 6)
        #expect(newest?.skipped == 3, "Frames 3, 4 and 5 were still ready")
        #expect(Self.take(mailbox, at: 10_000) == nil)
    }

    @Test func releasedSlotsAreUsedAgainWithoutOverwriting() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565, slotCount: 3)
        for sequence in 1...30 {
            Self.submit(mailbox, value: UInt16(sequence), sequence: UInt64(sequence), nominalTime: UInt64(sequence))
            #expect(Self.take(mailbox, at: UInt64(sequence))?.value == UInt16(sequence))
        }
        #expect(mailbox.counters == MailboxCounters(published: 30, overwritten: 0))
    }

    @Test func aHeldFrameIsNeverOverwritten() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565, slotCount: 3)
        Self.submit(mailbox, value: 1, sequence: 1, nominalTime: 1)
        guard case let .frame(held, _, _) = mailbox.takeFrame(presentationTime: 1, latency: 0) else {
            Issue.record("Frame 1 was not taken")
            return
        }
        for sequence in 2...10 {
            Self.submit(mailbox, value: UInt16(sequence), sequence: UInt64(sequence), nominalTime: UInt64(sequence))
        }
        #expect(held.pixels.load(as: UInt16.self) == 1, "The producer must not write into a slot the consumer holds")
        mailbox.release(held)
        #expect(Self.take(mailbox, at: 100)?.value == 10)
    }

    @Test func copiesRowsWithoutThePadding() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565)
        // Each row holds its row number in its 240 visible pixels and 0xDEAD in the padding.
        var pixels = [UInt16](repeating: 0xDEAD, count: 256 * 160)
        for row in 0..<160 {
            for column in 0..<240 {
                pixels[row * 256 + column] = UInt16(row)
            }
        }
        mailbox.submit(pixels: pixels.span.bytes, width: 240, height: 160, bytesPerRow: 512, format: .rgb565,
                       stamp: FrameStamp(sequence: 1, nominalTime: 0))
        guard case let .frame(frame, _, _) = mailbox.takeFrame(presentationTime: 0, latency: 0) else {
            Issue.record("No frame")
            return
        }
        defer { mailbox.release(frame) }
        #expect(frame.width == 240)
        #expect(frame.height == 160)
        #expect(frame.bytesPerRow == 480)
        let copied = UnsafeBufferPointer(start: frame.pixels.assumingMemoryBound(to: UInt16.self), count: 240 * 160)
        var wrong = 0
        for row in 0..<160 {
            for column in 0..<240 where copied[row * 240 + column] != UInt16(row) {
                wrong += 1
            }
        }
        #expect(wrong == 0)
    }

    @Test func reportsALateFrameWhenTheNextOneWasDueButIsMissing() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565)
        Self.submit(mailbox, value: 1, sequence: 1, nominalTime: 0)
        Self.submit(mailbox, value: 2, sequence: 2, nominalTime: 100)
        // Frame 3 would be due at 200: at 150 nothing is late yet, at 250 it is.
        #expect(Self.take(mailbox, at: 150)?.isLate == false)
        Self.submit(mailbox, value: 3, sequence: 3, nominalTime: 200)
        #expect(Self.take(mailbox, at: 350)?.isLate == true, "Frame 4 was due at 300")
    }

    @Test func dropsPicturesInAnotherFormatOrWithoutRows() {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565)
        let pixels = [UInt32](repeating: 0, count: 240 * 160)
        mailbox.submit(pixels: pixels.span.bytes, width: 240, height: 160, bytesPerRow: 960, format: .xrgb8888,
                       stamp: FrameStamp(sequence: 1, nominalTime: 0))
        let short = [UInt16](repeating: 0, count: 100)
        mailbox.submit(pixels: short.span.bytes, width: 240, height: 160, bytesPerRow: 480, format: .rgb565,
                       stamp: FrameStamp(sequence: 2, nominalTime: 0))
        #expect(mailbox.counters.published == 0)
    }

    @Test func holdsXRGB8888Pictures() {
        let geometry = VideoGeometry(baseWidth: 256, baseHeight: 192, maxWidth: 256, maxHeight: 384, aspectRatio: 4.0 / 3.0)
        let mailbox = FrameMailbox(geometry: geometry, format: .xrgb8888)
        let pixels = [UInt32](repeating: 0x00FF_8040, count: 256 * 192)
        mailbox.submit(pixels: pixels.span.bytes, width: 256, height: 192, bytesPerRow: 1024, format: .xrgb8888,
                       stamp: FrameStamp(sequence: 1, nominalTime: 0))
        guard case let .frame(frame, _, _) = mailbox.takeFrame(presentationTime: 0, latency: 0) else {
            Issue.record("No frame")
            return
        }
        defer { mailbox.release(frame) }
        #expect(frame.height == 192)
        #expect(frame.bytesPerRow == 1024)
        #expect(frame.pixels.load(fromByteOffset: 1023 * 4, as: UInt32.self) == 0x00FF_8040)
    }

    /// Two threads under full load: every picture carries its sequence number
    /// in all pixels, so a torn picture mixes two numbers.
    @Test func noTornOrReorderedPicturesUnderLoad() async throws {
        let mailbox = FrameMailbox(geometry: Self.geometry, format: .rgb565)
        let stop = Atomic<Bool>(false)
        let produced = Atomic<Int>(0)
        let producer = Thread {
            var pixels = [UInt16](repeating: 0, count: 240 * 160)
            var sequence: UInt64 = 0
            while !stop.load(ordering: .relaxed) {
                sequence += 1
                let value = UInt16(truncatingIfNeeded: sequence)
                pixels.withUnsafeMutableBufferPointer { buffer in
                    buffer.update(repeating: value)
                }
                mailbox.submit(pixels: pixels.span.bytes, width: 240, height: 160, bytesPerRow: 480, format: .rgb565,
                               stamp: FrameStamp(sequence: sequence, nominalTime: sequence))
                produced.store(Int(sequence), ordering: .relaxed)
            }
        }
        producer.start()

        var taken = 0
        var torn = 0
        var reordered = 0
        var last: UInt64 = 0
        let end = Date.now.addingTimeInterval(1.5)
        while Date.now < end {
            guard case let .frame(frame, _, _) = mailbox.takeFrame(presentationTime: .max, latency: 0) else { continue }
            let pixels = UnsafeBufferPointer(start: frame.pixels.assumingMemoryBound(to: UInt16.self), count: 240 * 160)
            let expected = UInt16(truncatingIfNeeded: frame.sequence)
            if pixels.contains(where: { $0 != expected }) {
                torn += 1
            }
            if frame.sequence <= last {
                reordered += 1
            }
            last = frame.sequence
            taken += 1
            mailbox.release(frame)
            // Now and then the consumer falls behind, so that the producer
            // has to overwrite unshown frames while the consumer works.
            if taken % 8 == 0 {
                usleep(5_000)
            }
        }
        stop.store(true, ordering: .relaxed)

        #expect(taken > 100)
        #expect(produced.load(ordering: .relaxed) >= taken)
        #expect(mailbox.counters.overwritten > 0)
        #expect(torn == 0)
        #expect(reordered == 0)
    }
}
