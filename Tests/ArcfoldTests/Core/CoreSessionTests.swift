import Foundation
import LibretroKit
import Testing

/// Every test that loads a session with the real mGBA core from the app
/// bundle and `selftest.gba` from the test bundle (ADR 0005, section 10).
/// Serialized, because libretro callbacks carry no context and only one core
/// can be active per process. The nested suites follow in extensions.
@Suite(.serialized)
struct CoreSessionTests {}

// MARK: - Start

extension CoreSessionTests {
    @Suite struct Start {
        @Test func mGBAReportsTheGBAPictureAndSound() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.configuration())
            #expect(session.state == .idle)

            let systemFolder = folder.systemDirectory
            #expect(!FileManager.default.fileExists(atPath: systemFolder.path(percentEncoded: false)))

            let info = try await session.load()

            #expect(session.state == .ready)
            // load() creates a missing system folder; it stays empty.
            #expect(try FileManager.default.contentsOfDirectory(atPath: systemFolder.path(percentEncoded: false)).isEmpty)
            #expect(info.system.libraryName == "mGBA")
            #expect(info.system.libraryVersion == "0.10.5")
            #expect(info.geometry.baseWidth == 240)
            #expect(info.geometry.baseHeight == 160)
            #expect(info.geometry.maxWidth == 240)
            #expect(info.geometry.maxHeight == 160)
            #expect(abs(info.geometry.aspectRatio - 1.5) < 1e-6)
            #expect(info.pixelFormat == .rgb565)
            #expect(abs(info.timing.framesPerSecond - 59.7275) < 1e-4)
            #expect(info.timing.sampleRate == 32_768)
            #expect(session.stats.snapshot().framesEmulated == 0)
            _ = await session.stop()
        }

        @Test func theFrameCounterInThePictureIsTheFrameNumberMinusSix() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.configuration())
            _ = try await session.load()
            let pictures = PictureRecorder(capturing: [60, 300])
            session.connect(video: pictures, audio: SoundRecorder())

            await session.runFrames(300)

            #expect(session.state == .paused)
            #expect(pictures.picture(60)?.frameCounter == 54)
            #expect(pictures.picture(300)?.frameCounter == 294)
            #expect(pictures.picture(300)?.bootCounter == 1)
            // mGBA delivers a picture every frame, always the same shape.
            #expect(pictures.stamps.map(\.sequence) == Array(1...300))
            #expect(pictures.shapes == [PictureRecorder.Shape(width: 240, height: 160, bytesPerRow: 512, format: .rgb565)])
            #expect(session.stats.snapshot().framesEmulated == 300)

            let summary = await session.stop()
            #expect(summary.framesEmulated == 300)
            #expect(session.state == .stopped)
        }
    }
}

// MARK: - Determinism

extension CoreSessionTests {
    @Suite struct Determinism {
        /// SHA-256 of the visible pixels with a fresh battery save, recorded with
        /// mGBA 0.10.5 in the iOS 27.1 Simulator on 7 November 2026. They start
        /// with the 16 digits the macOS build of the same core gave
        /// (docs/adr/0005/selftest-mgba-macos.txt).
        static let expected: [UInt64: String] = [
            1: "53430f5a5f2f35d81caeb2b710000a6d1d6b530f532418dc4d3dbdbf6143a37a",
            60: "c7e16708d892921a3b64a19df37dc46c68157c40a2e5d2f3da84b2d0735af5c3",
            300: "74a711472bbc92974de861af38c010e2ec96389bf0032342bc4321f75b7062e6",
        ]

        @Test func twoSessionsDrawTheSamePictures() async throws {
            var runs: [[UInt64: String]] = []
            for _ in 0..<2 {
                let folder = try SessionFolder()
                let session = EmulationSession(configuration: try folder.configuration())
                _ = try await session.load()
                let pictures = PictureRecorder(capturing: Set(Self.expected.keys))
                session.connect(video: pictures, audio: SoundRecorder())
                await session.runFrames(300)
                _ = await session.stop()
                var hashes: [UInt64: String] = [:]
                for frame in Self.expected.keys {
                    hashes[frame] = pictures.picture(frame)?.sha256
                }
                runs.append(hashes)
            }
            #expect(runs[0] == runs[1])
            #expect(runs[0] == Self.expected)
        }
    }
}

// MARK: - Sound and input

extension CoreSessionTests {
    /// Frames 1 to 300 one by one, with A held in frames 100 to 300.
    struct SelftestRun {
        var pictures: PictureRecorder
        var sound: SoundRecorder
        /// Writes and audio frames of each frame, index 0 is frame 1.
        var writesPerFrame: [Int]
        var audioFramesPerFrame: [Int]
        /// Audio frames written before each frame; index 0 is frame 1.
        var audioFramesBefore: [Int]

        static func run() async throws -> SelftestRun {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.configuration())
            _ = try await session.load()
            let pictures = PictureRecorder(capturing: [99, 300])
            let sound = SoundRecorder()
            session.connect(video: pictures, audio: sound)
            var writesPerFrame: [Int] = []
            var audioFramesPerFrame: [Int] = []
            var audioFramesBefore: [Int] = []
            for frame in 1...300 {
                if frame == 100 {
                    session.input.set(.a, from: .controller)
                }
                let writesBefore = sound.writes
                audioFramesBefore.append(writesBefore.reduce(0, +))
                await session.runFrames(1)
                let writesAfter = sound.writes
                let new = writesAfter.dropFirst(writesBefore.count)
                writesPerFrame.append(new.count)
                audioFramesPerFrame.append(new.reduce(0, +))
            }
            session.input.set([], from: .controller)
            _ = await session.stop()
            return SelftestRun(
                pictures: pictures, sound: sound, writesPerFrame: writesPerFrame,
                audioFramesPerFrame: audioFramesPerFrame, audioFramesBefore: audioFramesBefore
            )
        }

        /// The interleaved samples of frames `range` (1-based, inclusive).
        func samples(frames range: ClosedRange<Int>) -> ArraySlice<Int16> {
            let all = sound.samples
            let start = 2 * audioFramesBefore[range.lowerBound - 1]
            let end = range.upperBound < audioFramesBefore.count ? 2 * audioFramesBefore[range.upperBound] : all.count
            return all[start..<end]
        }
    }

    @Suite struct Sound {
        @Test func oneBatchPerFrameWithA440HertzToneAnd880WithA() async throws {
            let run = try await SelftestRun.run()

            #expect(run.writesPerFrame.allSatisfy { $0 == 1 })
            let fromSecondFrame = run.audioFramesPerFrame.dropFirst()
            #expect(fromSecondFrame.allSatisfy { (545...552).contains($0) }, "\(Set(fromSecondFrame).sorted())")
            let mean = Double(fromSecondFrame.reduce(0, +)) / Double(fromSecondFrame.count)
            #expect(abs(mean - 548.63) <= 0.5, "mean \(mean)")

            let low = toneFrequency(of: run.samples(frames: 20...95), sampleRate: 32_768)
            let high = toneFrequency(of: run.samples(frames: 110...300), sampleRate: 32_768)
            #expect(abs(low - 440) <= 2, "\(low) Hz")
            #expect(abs(high - 880) <= 2, "\(high) Hz")
        }
    }

    @Suite struct Input {
        @Test func aHeldFromFrame100SetsBitZeroOfTheKeyRow() async throws {
            let run = try await SelftestRun.run()

            #expect(run.pictures.picture(99)?.keys == 0)
            #expect(run.pictures.picture(300)?.keys == 0b1)
        }
    }
}

// MARK: - Battery save

extension CoreSessionTests {
    @Suite struct BatterySave {
        @Test func theSaveSurvivesASecondSession() async throws {
            let folder = try SessionFolder()

            let first = EmulationSession(configuration: try folder.configuration())
            _ = try await first.load()
            first.connect(video: PictureRecorder(), audio: SoundRecorder())
            await first.runFrames(300)
            _ = await first.stop()
            let firstEvents = await first.events.collect()

            let saved = try Data(contentsOf: folder.batterySave)
            #expect(saved.count == 32_768)
            #expect(saved.prefix(4) == Data("ARCF".utf8))
            #expect(saved[4] == 0x01)
            // The heartbeat: frame counter 294 / 64.
            #expect(saved[5] == 4)
            #expect(firstEvents.contains(.batterySaveWritten(bytes: 32_768)))
            #expect(!firstEvents.contains { if case .batterySaveFailed = $0 { true } else { false } })

            let second = EmulationSession(configuration: try folder.configuration())
            _ = try await second.load()
            let pictures = PictureRecorder(capturing: [300])
            second.connect(video: pictures, audio: SoundRecorder())
            await second.runFrames(300)
            _ = await second.stop()

            #expect(pictures.picture(300)?.bootCounter == 2)
            let savedAgain = try Data(contentsOf: folder.batterySave)
            #expect(savedAgain.count == 32_768)
            #expect(savedAgain[4] == 0x02)
            #expect(FileManager.default.fileExists(atPath: folder.url.appending(path: "battery.sav.bak").path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: "battery.sav.tmp").path(percentEncoded: false)))
        }

        @Test func pauseAndSaveBatteryNowWriteAtOnce() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.configuration())
            _ = try await session.load()
            session.connect(video: PictureRecorder(), audio: SoundRecorder())

            // Frame 10: the program wrote its boot counter, no periodic check ran yet.
            await session.runFrames(10)
            #expect(!FileManager.default.fileExists(atPath: folder.batterySave.path(percentEncoded: false)))
            await session.pause()
            #expect(try Data(contentsOf: folder.batterySave)[4] == 0x01)

            // The heartbeat changes at frame counter 64, frame 70.
            await session.runFrames(65)
            try await session.saveBatteryNow()
            #expect(try Data(contentsOf: folder.batterySave)[5] == 1)
            _ = await session.stop()
        }
    }
}

// MARK: - Environment

extension CoreSessionTests {
    @Suite struct Environment {
        @Test func mGBAUsesOnlyCommandsTheHostSupportsExceptMemoryMapsAndAchievements() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.configuration())
            _ = try await session.load()
            session.connect(video: PictureRecorder(), audio: SoundRecorder())
            await session.runFrames(300)

            let summary = await session.stop()

            let refused: Set<UInt32> = [36 | 0x10000, 42 | 0x10000]
            #expect(summary.unhandledEnvironmentCommands == refused)
            #expect(summary.framesEmulated == 300)
            // GET_VARIABLE_UPDATE once per frame, GET_CORE_OPTIONS_VERSION and SET_VARIABLES once.
            #expect(summary.environmentCalls[17] == 300)
            #expect(summary.environmentCalls[52] == 1)
            #expect(summary.environmentCalls[16] == 1)
        }
    }
}

// MARK: - Lifecycle with the real clock

extension CoreSessionTests {
    @Suite struct Lifecycle {
        @Test func loadRunPauseResumeStopInRealTime() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.configuration(pacing: .realTime))
            let info = try await session.load()
            let pictures = PictureRecorder()
            // 35 ms, the lowest target level of ADR 0005.
            let sound = ClockedSoundSink(sampleRate: info.timing.sampleRate, targetFrames: 1_147)
            session.connect(video: pictures, audio: sound)

            session.resume()
            try await waitUntil { pictures.count >= 120 }
            #expect(session.state == .running)
            await session.pause()
            #expect(session.state == .paused)
            let pausedAt = pictures.count
            #expect(session.stats.snapshot().framesEmulated == UInt64(pausedAt))
            try await Task.sleep(for: .milliseconds(300))
            #expect(pictures.count == pausedAt)
            #expect(FileManager.default.fileExists(atPath: folder.batterySave.path(percentEncoded: false)))
            // A second pause, as the app sends for inactive and then background,
            // keeps the frame rate of the last interval with frames.
            await session.pause()
            #expect(session.stats.snapshot().framesPerSecond > 50)

            session.resume()
            try await waitUntil { pictures.count >= pausedAt + 60 }
            let summary = await session.stop()
            #expect(session.state == .stopped)
            #expect(summary.framesEmulated >= UInt64(pausedAt + 60))
            #expect(try Data(contentsOf: folder.batterySave).count == 32_768)

            // Plausibility only: the Simulator runs on the Mac's chip.
            let arrivals = pictures.arrivals
            let ticks = Double(arrivals[119] - arrivals[9])
            let rate = 110 / (ticks * Self.secondsPerTick)
            #expect(abs(rate - 59.7) <= 1, "\(rate) frames per second")
        }

        static let secondsPerTick: Double = {
            var info = mach_timebase_info_data_t()
            mach_timebase_info(&info)
            return Double(info.numer) / Double(info.denom) / 1_000_000_000
        }()
    }
}

// MARK: - Failures

extension CoreSessionTests {
    @Suite struct Failures {
        @Test func aMissingCoreFailsToLoad() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.configuration(coreName: "missing_libretro"))

            let error = await #expect(throws: SessionError.self) {
                _ = try await session.load()
            }

            guard case .core(.frameworkNotFound(name: "missing_libretro", path: _)) = error else {
                Issue.record("Expected frameworkNotFound, got \(String(describing: error))")
                return
            }
            #expect(session.state == .failed)
            _ = await session.stop()
            #expect(session.state == .stopped)
        }

        @Test func aMissingGameFailsToLoadAndLeavesTheSlotFree() async throws {
            let folder = try SessionFolder()
            let missing = folder.url.appending(path: "missing.gba")
            let session = EmulationSession(configuration: try folder.configuration(game: missing))

            let error = await #expect(throws: SessionError.self) {
                _ = try await session.load()
            }

            guard case let .unreadableGame(path, _) = error else {
                Issue.record("Expected unreadableGame, got \(String(describing: error))")
                return
            }
            #expect(path.hasSuffix("missing.gba"))
            #expect(session.state == .failed)

            // The core was deinitialized and the callback slot released.
            let next = EmulationSession(configuration: try folder.configuration())
            _ = try await next.load()
            #expect(next.state == .ready)
            _ = await next.stop()
        }

        @Test func aSecondSessionCannotLoadWhileTheFirstRuns() async throws {
            let folder = try SessionFolder()
            let otherFolder = try SessionFolder()
            let first = EmulationSession(configuration: try folder.configuration())
            _ = try await first.load()

            let second = EmulationSession(configuration: try otherFolder.configuration())
            await #expect(throws: SessionError.anotherSessionActive) {
                _ = try await second.load()
            }
            #expect(second.state == .failed)

            _ = await first.stop()
            let third = EmulationSession(configuration: try otherFolder.configuration())
            _ = try await third.load()
            _ = await third.stop()
        }
    }
}
