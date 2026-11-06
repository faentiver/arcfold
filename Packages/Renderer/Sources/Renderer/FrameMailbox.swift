// Renderer shows what a core produces (docs/PLAN.md, section 5; ADR 0005):
// FrameMailbox and GameScreen for the picture, AudioRing and AudioOutput for
// the sound. Software cores only in M1; GPU cores (PSP) follow in M3.

import LibretroKit

/// Hands pictures from the emulation thread to the screen without tearing,
/// locks or allocations.
///
/// The emulation thread (`VideoSink`) copies each picture into a free slot;
/// the display link takes the newest frame whose nominal time is due. When no
/// slot is free, the oldest unshown frame is overwritten. All slots are
/// allocated once in `init`. One producer and one consumer.
public final class FrameMailbox: VideoSink, @unchecked Sendable {
    /// - Parameters:
    ///   - geometry: Slots are sized for `maxWidth x maxHeight`.
    ///   - format: The pixel format of the session; RGB565 and XRGB8888.
    ///   - slotCount: At least 3; 4 leaves room for a frame in flight to the GPU.
    public init(geometry: VideoGeometry, format: PixelFormat, slotCount: Int = 4) {
        fatalError("M1 track A")
    }

    public func submit(pixels: RawSpan, width: Int, height: Int, bytesPerRow: Int,
                       format: PixelFormat, stamp: FrameStamp) {
        fatalError("M1 track A")
    }

    /// Producer-side counters, read atomically.
    public var counters: MailboxCounters {
        fatalError("M1 track A")
    }
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
