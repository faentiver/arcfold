import LibretroKit
import Renderer
import Testing

/// The contract between the two M1 tracks: Renderer's mailbox and ring are the
/// sinks LibretroKit's session writes into (ADR 0005).
struct SinkConformanceTests {
    @Test func mailboxAndRingAreLibretroKitSinks() {
        #expect((FrameMailbox.self as Any) is any VideoSink.Type)
        #expect((AudioRing.self as Any) is any AudioSink.Type)
    }
}
