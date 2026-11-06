import CLibretro
import Foundation
@testable import LibretroKit
import Testing

/// What a session promises without a core: the methods never block and are
/// safe in every state (ADR 0005, section 2). Loading with a real core is
/// tested in ArcfoldTests/Core.
struct SessionContractTests {
    @Test func anUnloadedSessionAnswersEveryCommandAtOnce() async throws {
        let session = EmulationSession(configuration: Self.configuration())
        #expect(session.state == .idle)
        session.input.set(.a, from: .touch)
        #expect(session.input.heldButtons == .a)
        #expect(session.stats.snapshot().framesEmulated == 0)

        session.resume()
        await session.pause()
        await session.runFrames(10)
        try await session.saveBatteryNow()
        #expect(session.state == .idle)

        let summary = await session.stop()
        #expect(session.state == .stopped)
        #expect(summary == SessionSummary(framesEmulated: 0, environmentCalls: [:], unhandledEnvironmentCommands: []))
        #expect(await session.stop() == summary)

        // The events finish with stop().
        var events: [SessionEvent] = []
        for await event in session.events {
            events.append(event)
        }
        #expect(events.isEmpty)
    }

    @Test func statesKeepTheirCodes() {
        let states: [SessionState] = [.idle, .loading, .ready, .running, .paused, .stopped, .failed]
        for state in states {
            #expect(SessionState(code: state.code) == state)
        }
        #expect(Set(states.map(\.code)).count == states.count)
    }

    @Test func statsPublishWhatTheThreadMeasured() {
        let stats = SessionStats()
        stats.publish(
            framesEmulated: 120, framesPerSecond: 59.73, lateFrames: 2, resyncs: 1,
            lastRunNanoseconds: 250_000, maxRunNanoseconds: 410_000, maxLatenessNanoseconds: 2_500_000,
            periodTrim: -0.0001
        )
        #expect(stats.snapshot() == SessionStats.Snapshot(
            framesEmulated: 120, framesPerSecond: 59.73, lateFrames: 2, resyncs: 1,
            lastRunTime: .microseconds(250), maxRunTime: .microseconds(410), maxLateness: .microseconds(2_500),
            periodTrim: -0.0001
        ))
    }

    @Test func coreLogLinesAreRateLimited() {
        var limiter = RateLimiter(ticksPerSecond: 1_000)
        for tick: UInt64 in 0..<UInt64(RateLimiter.linesPerSecond) {
            #expect(limiter.admit(at: tick) == .admitted(droppedBefore: 0))
        }
        #expect(limiter.admit(at: 500) == .dropped)
        #expect(limiter.admit(at: 999) == .dropped)
        // The next window reports what was dropped.
        #expect(limiter.admit(at: 1_000) == .admitted(droppedBefore: 2))
        #expect(limiter.admit(at: 1_001) == .admitted(droppedBefore: 0))
    }

    @Test func theLogShimStartsAtWarningLevel() {
        #expect(arcfold_log_minimum_level() == RETRO_LOG_WARN)
        var callback = retro_log_callback(log: nil)
        #expect(arcfold_log_fill_interface(&callback))
        #expect(callback.log != nil)
        #expect(!arcfold_log_fill_interface(nil))
    }

    static func configuration() -> SessionConfiguration {
        let folder = FileManager.default.temporaryDirectory.appending(path: "LibretroKitTests-\(UUID().uuidString)")
        return SessionConfiguration(
            coreName: "missing_libretro",
            game: folder.appending(path: "game.gba"),
            batterySave: folder.appending(path: "battery.sav"),
            systemDirectory: folder.appending(path: "System", directoryHint: .isDirectory),
            saveDirectory: folder,
            pacing: .unthrottled
        )
    }
}
