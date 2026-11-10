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

    /// melonDS DS plays at 33 513 982 / 1024 = 32 728.498046875 Hz, which ADR
    /// 0006 first gave as 32 728.5 Hz. The test feeds the core's exact rate,
    /// as the app does. The fraction survives in a format, but the source
    /// node converts from the nearest whole rate, 32 728 Hz, because its
    /// conversion from a fraction broke down after 80 to 90 s in the
    /// Simulator (docs/wissen/renderer.md). Fed at the core's rate, the output
    /// consumes at that rate. Underruns only appear in the printed line: the
    /// writer here runs on the main actor while other suites load the Mac,
    /// unlike the emulation thread of the app.
    @Test func playsTheFractionalRateOfTheDS() async throws {
        let rate = 33_513_982.0 / 1024
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 2, interleaved: true))
        #expect(format.sampleRate == rate)
        #expect(format.streamDescription.pointee.mSampleRate == rate)
        // The node's rate lies 15 ppm below the core's; the first assumption
        // of 32 728.5 Hz would have given 32 729 Hz.
        #expect(AudioOutput.nodeSampleRate(for: rate) == 32_728)
        #expect(AudioOutput.nodeSampleRate(for: 32_728.5) == 32_729)
        #expect(AudioOutput.nodeSampleRate(for: 32_768) == 32_768, "mGBA keeps its rate")

        let ring = AudioRing()
        let output = AudioOutput(ring: ring, sampleRate: rate)
        try await output.start()
        defer { output.stop() }
        let route = output.route
        #expect(ring.counters.targetFrames == Int((max(0.035, route.ioBufferDuration + 0.020) * rate).rounded(.up)))

        // Silence on an absolute schedule at the core's rate, in steps of
        // about 8 ms, for 2.5 s, with 4096 frames (125 ms) ahead, as the clock
        // of the emulation keeps a reserve; the consumption is measured over
        // the last 1.5 s. The Simulator renders about 350 frames per call.
        func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        }
        let clock = ContinuousClock()
        let start = clock.now
        let silence = [Int16](repeating: 0, count: 2 * 2048)
        let reserve = 4096
        var written = 0
        var consuming = false
        var mark: (time: ContinuousClock.Instant, consumed: Int, underruns: UInt64)?
        var measured: (seconds: Double, frames: Int)?
        while start.duration(to: clock.now) < .milliseconds(2500) {
            let now = clock.now
            var missing = Int(seconds(start.duration(to: now)) * rate) + reserve - written
            while missing > 0 {
                let frames = min(missing, 2048)
                consuming = ring.write(silence.span.extracting(0..<2 * frames)).isConsuming || consuming
                written += frames
                missing -= frames
            }
            let counters = ring.counters
            let consumed = written - counters.bufferedFrames - Int(counters.droppedFrames)
            if let mark {
                measured = (seconds(mark.time.duration(to: now)), consumed - mark.consumed)
            } else if start.duration(to: now) >= .milliseconds(1000) {
                mark = (now, consumed, counters.underruns)
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        let counters = ring.counters
        #expect(consuming, "The ring never reported that the output pulls")
        // Consumed frames are counted exactly, whatever ran short or over. A
        // rate taken as 44.1 or 48 kHz by mistake would be 35 to 47 % too
        // fast. The bounds are wide, because under load the Simulator's audio
        // output stalls and consumes less; a quiet run gives 0.01 % (renderer.md).
        let (seconds, frames) = try #require(measured)
        let consumptionRate = Double(frames) / seconds
        #expect(consumptionRate > rate * 0.5 && consumptionRate < rate * 1.15,
                "Consumed \(consumptionRate) frames per second")
        #expect(counters.renderCalls > 0)
        print("AudioOutput at \(rate) Hz: consumed \(consumptionRate) frames/s over \(seconds) s, underruns \(counters.underruns) (\(mark?.underruns ?? 0) in the first second), dropped \(counters.droppedFrames), primes \(counters.primes), calls \(counters.renderCalls), largest request \(counters.largestRequest), hardware \(route.hardwareSampleRate) Hz, IO \(route.ioBufferDuration * 1000) ms")
    }
}
