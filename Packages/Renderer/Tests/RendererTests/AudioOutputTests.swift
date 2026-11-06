import AVFAudio
import LibretroKit
import Renderer
import Testing

/// The real engine graph: session, source node with the C render block,
/// conversion to the hardware rate (ADR 0005, section 6). Plays silence.
/// Serialized, because all outputs share the one audio session.
@MainActor
@Suite(.serialized)
struct AudioOutputTests {
    @Test func startsPullsFromTheRingAndStops() async throws {
        let ring = AudioRing()
        let output = AudioOutput(ring: ring, sampleRate: 32_768)
        try await output.start()

        let route = output.route
        #expect(route.hardwareSampleRate > 0)
        #expect(route.ioBufferDuration > 0)
        // max(35 ms, IO buffer + 20 ms) at 32 768 Hz
        let expectedTarget = Int((max(0.035, route.ioBufferDuration + 0.020) * 32_768).rounded(.up))
        #expect(ring.counters.targetFrames == expectedTarget)

        // One frame of silence every 16 ms, as the emulation would deliver it.
        let frame = [Int16](repeating: 0, count: 2 * 548)
        var consuming = false
        for _ in 0..<90 {
            consuming = ring.write(frame.span).isConsuming || consuming
            try await Task.sleep(for: .milliseconds(16))
        }
        output.stop()

        let counters = ring.counters
        #expect(counters.renderCalls > 0, "The render block never ran")
        #expect(counters.largestRequest > 0)
        #expect(consuming, "The ring never reported that the output pulls")
    }

    @Test func suspendAndResumeDoNotCountUnderruns() async throws {
        let ring = AudioRing()
        let output = AudioOutput(ring: ring, sampleRate: 32_768)
        try await output.start()
        defer { output.stop() }

        output.suspend()
        try await Task.sleep(for: .milliseconds(200))
        let suspended = ring.counters
        #expect(suspended.underruns == 0)
        #expect(suspended.renderCalls > 0)

        output.resume()
        try await Task.sleep(for: .milliseconds(100))
        #expect(ring.counters.underruns == 0, "Priming after a resume is not an underrun")
        #expect(ring.counters.primes >= 2)
    }
}
