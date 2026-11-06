import SwiftUI
import UIKit

/// The picture of a running game: the newest due frame of a `FrameMailbox`,
/// at the largest whole-number scale that fits, centred, black around it.
///
/// Drawn with Metal into a `CAMetalLayer`, paced by a `CAMetalDisplayLink` on
/// the main run loop. The main thread never waits for the emulation or the GPU.
public struct GameScreen: UIViewRepresentable {
    /// - Parameters:
    ///   - mailbox: The frames to show.
    ///   - stats: Where the screen counts what it presented.
    ///   - isPaused: Stops the display link and keeps the last picture.
    public init(mailbox: FrameMailbox, stats: PresentationStats, isPaused: Bool = false) {
        fatalError("M1 track A")
    }

    public func makeUIView(context: Context) -> UIView {
        fatalError("M1 track A")
    }

    public func updateUIView(_ view: UIView, context: Context) {
        fatalError("M1 track A")
    }
}

/// What the screen presented, for the debug overlay. Written on the main
/// thread by `GameScreen`, readable from anywhere.
public final class PresentationStats: Sendable {
    /// One reading of all values.
    public struct Snapshot: Sendable, Hashable {
        /// Display link callbacks since the screen appeared.
        public var displayUpdates: UInt64
        /// The refresh rate the display link runs at, in Hz.
        public var refreshRate: Double
        /// Frames shown for the first time.
        public var framesShown: UInt64
        /// Display updates that kept the previous frame because no new one was due.
        public var framesRepeated: UInt64
        /// Delivered frames that were never shown.
        public var framesSkipped: UInt64
        /// Updates where the due frame was not ready yet and an older one was shown.
        public var lateSelections: UInt64
        /// Updates skipped because the GPU still used the next texture.
        public var gpuBusy: UInt64

        public init(
            displayUpdates: UInt64, refreshRate: Double, framesShown: UInt64, framesRepeated: UInt64,
            framesSkipped: UInt64, lateSelections: UInt64, gpuBusy: UInt64
        ) {
            self.displayUpdates = displayUpdates
            self.refreshRate = refreshRate
            self.framesShown = framesShown
            self.framesRepeated = framesRepeated
            self.framesSkipped = framesSkipped
            self.lateSelections = lateSelections
            self.gpuBusy = gpuBusy
        }
    }

    public init() {
        fatalError("M1 track A")
    }

    /// The current values.
    public func snapshot() -> Snapshot {
        fatalError("M1 track A")
    }
}
