@testable import Arcfold
import Foundation
import LibretroKit
import Testing

/// Every test that loads a session with the real melonDS DS core from the app
/// bundle and `selftest.nds` from the test bundle (ADR 0006, section 14),
/// configured like `GameSystem.ds` with the console clock at a fixed start.
/// Nested in `CoreSessionTests`, so that these tests run one after another
/// together with the GBA tests: only one core can be active per process.
extension CoreSessionTests {
    @Suite struct DS {}
}

// MARK: - Start

extension CoreSessionTests.DS {
    @Suite struct Start {
        @Test func melonDSDSReportsBothScreensAsOnePictureAndTheDSClock() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())

            let info = try await session.load()

            #expect(session.state == .ready)
            #expect(info.system.libraryName == "melonDS DS")
            #expect(info.system.libraryVersion == "1.4.0")
            #expect(info.pixelFormat == .xrgb8888)
            #expect(info.geometry.baseWidth == 256)
            #expect(info.geometry.baseHeight == 384)
            #expect(info.geometry.maxWidth == 1024)
            #expect(info.geometry.maxHeight == 576)
            #expect(abs(info.geometry.aspectRatio - 256.0 / 384.0) < 1e-6)
            // The DS clock of 33 513 982 Hz: 560 190 cycles per frame, one
            // sample every 1024 cycles, about 59.826098 frames per second and
            // 32 728.498 Hz.
            #expect(info.timing.framesPerSecond == 33_513_982.0 / 560_190.0)
            #expect(info.timing.sampleRate == 33_513_982.0 / 1024.0)
            #expect(abs(info.timing.framesPerSecond - 59.826098) < 1e-6)

            session.connect(video: PictureRecorder(), audio: SoundRecorder())
            await session.runFrames(60)
            _ = await session.stop()

            // The core never looks for BIOS or firmware files (melonds_sysfile_mode
            // builtin). It keeps only the Wi-Fi settings of its generated firmware
            // in the system folder, and nothing in its folder next to the saves.
            let system = folder.systemDirectory.path(percentEncoded: false)
            let systemFiles = try FileManager.default.subpathsOfDirectory(atPath: system)
            #expect(Set(systemFiles) == ["melonDS DS", "melonDS DS/wfcsettings.bin"])
            let settings = try FileManager.default.attributesOfItem(atPath: system + "/melonDS DS/wfcsettings.bin")
            #expect((settings[.size] as? NSNumber)?.intValue == 2304)
            let saveFolder = folder.url.appending(path: "melonDS DS", directoryHint: .isDirectory).path(percentEncoded: false)
            #expect(try FileManager.default.contentsOfDirectory(atPath: saveFolder).isEmpty)
        }

        @Test func everyFrameIsOnePictureWithTheFrameCountersOfBothProcessors() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await session.load()
            let pictures = PictureRecorder(capturing: [60, 300])
            session.connect(video: pictures, audio: SoundRecorder())

            await session.runFrames(300)

            // One picture per retro_run, always both screens one above the
            // other without padding.
            #expect(pictures.stamps.map(\.sequence) == Array(1...300))
            #expect(pictures.shapes == [PictureRecorder.Shape(width: 256, height: 384, bytesPerRow: 1024, format: .xrgb8888)])
            let at60 = DSSelftestPicture(try #require(pictures.picture(60)))
            let at300 = DSSelftestPicture(try #require(pictures.picture(300)))
            #expect(at60.hasBothScreens)
            #expect(at60.arm9Frames == 53)
            #expect(at60.arm7Frames == 59)
            #expect(at300.arm9Frames == 293)
            #expect(at300.arm7Frames == 299)
            #expect(session.stats.snapshot().framesEmulated == 300)
            let summary = await session.stop()
            #expect(summary.framesEmulated == 300)
        }
    }
}

// MARK: - Determinism

extension CoreSessionTests.DS {
    @Suite struct Determinism {
        /// SHA-256 of the visible pixels (row by row, bytes as delivered) with
        /// a new save memory filled with 0xFF, recorded with melonDS DS 1.4.0 in
        /// the iOS 27.1 Simulator on 7 November 2026. They equal the values of
        /// the macOS build from the exploration, whose save memory started at
        /// 0x00: either way the magic is missing, and the picture shows nothing
        /// else of the save memory.
        static let expected: [UInt64: String] = [
            1: "076545ea43c5bb9f7ea888579db152faf36bc4d87cc9336ed48392af1e884e16",
            60: "26f92f38da2bfa57536f93decdb6202bdc80acd6f8190178fe6f29c272b9711c",
            300: "7e908360fda9529cae419c77c215396d2fbf8878454716dd29798c88018a0efb",
        ]

        @Test func twoSessionsDrawTheSamePictures() async throws {
            var runs: [[UInt64: String]] = []
            for _ in 0..<2 {
                let folder = try SessionFolder()
                let session = EmulationSession(configuration: try folder.dsConfiguration())
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

// MARK: - Sound

extension CoreSessionTests.DS {
    /// Frames 1 to 300 one by one, with A held from frame 100 on.
    struct SoundRun {
        var sound: SoundRecorder
        /// Writes and audio frames of each frame; index 0 is frame 1.
        var writesPerFrame: [Int]
        var audioFramesPerFrame: [Int]
        /// Audio frames written before each frame; index 0 is frame 1.
        var audioFramesBefore: [Int]

        static func run() async throws -> SoundRun {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await session.load()
            let sound = SoundRecorder()
            session.connect(video: LatestPicture(), audio: sound)
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
                let new = sound.writes.dropFirst(writesBefore.count)
                writesPerFrame.append(new.count)
                audioFramesPerFrame.append(new.reduce(0, +))
            }
            session.input.set([], from: .controller)
            _ = await session.stop()
            return SoundRun(
                sound: sound, writesPerFrame: writesPerFrame,
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
            let run = try await SoundRun.run()

            #expect(run.writesPerFrame.allSatisfy { $0 == 1 })
            let frames = run.audioFramesPerFrame
            #expect(frames.allSatisfy { (546...548).contains($0) }, "\(Set(frames).sorted())")
            let mean = Double(frames.reduce(0, +)) / Double(frames.count)
            #expect(abs(mean - 547.06) <= 0.5, "mean \(mean)")

            let rate = 33_513_982.0 / 1024.0
            let low = toneFrequency(of: run.samples(frames: 20...95), sampleRate: rate)
            let high = toneFrequency(of: run.samples(frames: 110...300), sampleRate: rate)
            #expect(abs(low - 439.95) <= 2, "\(low) Hz")
            #expect(abs(high - 880.1) <= 2, "\(high) Hz")
        }
    }
}

// MARK: - Buttons

extension CoreSessionTests.DS {
    @Suite struct Buttons {
        /// The RetroPad buttons and the bit each sets in the program's key row:
        /// KEYINPUT order for bits 0 to 9, then X and Y from EXTKEYIN.
        static let bits: [(button: JoypadButtons, bit: Int)] = [
            (.a, 0), (.b, 1), (.select, 2), (.start, 3), (.right, 4), (.left, 5),
            (.up, 6), (.down, 7), (.r, 8), (.l, 9), (.x, 10), (.y, 11),
        ]

        @Test func everyRetroPadButtonPressesItsDSKey() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await session.load()
            let screen = LatestPicture()
            session.connect(video: screen, audio: SoundRecorder())
            await session.runFrames(30)
            #expect(screen.picture?.keys == 0)

            for (button, bit) in Self.bits {
                session.input.set(button, from: .controller)
                await session.runFrames(4)
                #expect(screen.picture?.keys == 1 << bit, "bit \(bit) held")
                session.input.set([], from: .controller)
                await session.runFrames(4)
                #expect(screen.picture?.keys == 0, "bit \(bit) released")
            }
            #expect(session.input.pressCount == 12)
            _ = await session.stop()
        }
    }
}

// MARK: - Touch

extension CoreSessionTests.DS {
    /// The touch screen through the libretro pointer, without the app: the
    /// pointer aimed at the centre of each pixel (ADR 0006, section 6).
    @Suite struct Touch {
        @Test func everyColumnAndEveryRowOfTheTouchScreenLandsOnItsPixel() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await session.load()
            let screen = LatestPicture()
            session.connect(video: screen, audio: SoundRecorder())
            await session.runFrames(30)
            let before = try #require(screen.picture?.touchCount)
            #expect(screen.picture?.crosshair == nil)

            let targets = (0..<256).map { DSPixel(x: $0, y: 100) } + (0..<192).map { DSPixel(x: 128, y: $0) }
            var misses: [String] = []
            var penMisses: [String] = []
            for target in targets {
                // Three frames pressed, two lifted: the blocks follow one frame
                // after the press, the crosshair two.
                session.input.setPointer(target.pointerOnTouchScreen)
                await session.runFrames(3)
                // While pressed, the key row shows the pen down (bit 12) and nothing else.
                let pressed = screen.picture?.keys
                if pressed != 1 << 12 {
                    penMisses.append("\(target): keys \(pressed.map { String($0, radix: 2) } ?? "?")")
                }
                session.input.setPointer(nil)
                await session.runFrames(2)
                let picture = try #require(screen.picture)
                let hits = picture.touchX == target.x && picture.touchY == target.y
                    && picture.rawX == target.x * 16 && picture.rawY == target.y * 16
                    && picture.crosshair == target && picture.keys == 0
                if !hits {
                    misses.append("\(target): \(picture.touchSummary), keys \(picture.keys.map { String($0, radix: 2) } ?? "?")")
                }
            }

            #expect(targets.count == 448)
            #expect(misses.isEmpty, "\(misses.count) of \(targets.count) missed, first: \(misses.prefix(5))")
            #expect(penMisses.isEmpty, "\(penMisses.count) without the pen bit, first: \(penMisses.prefix(5))")
            // One pen-down event per touch, counted modulo 256 by the program.
            #expect(screen.picture?.touchCount == (before + targets.count) % 256)
            #expect(session.input.pointerPressCount == UInt64(targets.count))
            #expect(session.input.lastPointerPress == targets.last?.pointerOnTouchScreen)
            #expect(session.input.pointer == nil)
            _ = await session.stop()
        }

        @Test func aTapShorterThanOneFrameStillTouches() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await session.load()
            let screen = LatestPicture()
            session.connect(video: screen, audio: SoundRecorder())
            await session.runFrames(30)
            let target = DSPixel(x: 37, y: 150)

            // Down and up again before the core polls: the latch holds the
            // press for exactly one poll.
            session.input.setPointer(target.pointerOnTouchScreen)
            session.input.setPointer(nil)
            await session.runFrames(1)
            await session.runFrames(3)

            let picture = try #require(screen.picture)
            #expect(picture.touchX == 37)
            #expect(picture.touchY == 150)
            #expect(picture.rawX == 37 * 16)
            #expect(picture.rawY == 150 * 16)
            #expect(picture.touchCount == 1)
            #expect(picture.crosshair == target)
            // What the debug overlay shows after such a tap.
            #expect(session.input.pointerPressCount == 1)
            #expect(session.input.lastPointerPress == target.pointerOnTouchScreen)
            #expect(session.input.pointer == nil)
            _ = await session.stop()
        }
    }
}

// MARK: - Battery save

extension CoreSessionTests.DS {
    @Suite struct BatterySave {
        @Test func aNewSaveMemoryStartsErasedAndTheBootCounterCountsThreeSessions() async throws {
            let folder = try SessionFolder()
            for boot in 1...3 {
                let session = EmulationSession(configuration: try folder.dsConfiguration())
                _ = try await session.load()
                let screen = LatestPicture()
                session.connect(video: screen, audio: SoundRecorder())
                await session.runFrames(300)
                let picture = try #require(screen.picture)
                _ = await session.stop()
                let events = await session.events.collect()

                #expect(picture.bootCounter == boot)
                // Bit 0, the magic, is missing in the erased memory of the first
                // boot; the boot record and the heartbeat read back; the ARM7 runs.
                #expect(picture.status == (boot == 1 ? 0x0E : 0x0F))
                // ARM7 frame 299: the heartbeat written at ARM7 frame 256 is 256 / 64.
                #expect(picture.heartbeat == 4)
                let saved = try Data(contentsOf: folder.batterySave)
                #expect(saved.count == 8192)
                #expect(saved.prefix(4) == Data("ARCF".utf8))
                #expect(saved[4] == UInt8(boot))
                #expect(saved[5] == 4)
                // The program writes bytes 0 to 5 only. The rest is what the
                // session filled the new memory with, like erased EEPROM.
                #expect(saved.dropFirst(6).allSatisfy { $0 == 0xFF })
                #expect(events.contains(.batterySaveWritten(bytes: 8192)))
                #expect(!events.contains { if case .batterySaveFailed = $0 { true } else { false } })
            }
            #expect(FileManager.default.fileExists(atPath: folder.url.appending(path: "battery.sav.bak").path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: "battery.sav.tmp").path(percentEncoded: false)))
        }

        @Test func withoutTheFillMelonDSDSStartsWithZeros() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration(fillsBlankSaveMemory: false))
            _ = try await session.load()
            session.connect(video: LatestPicture(), audio: SoundRecorder())
            await session.runFrames(300)
            _ = await session.stop()

            let saved = try Data(contentsOf: folder.batterySave)
            #expect(saved.count == 8192)
            #expect(Array(saved.prefix(6)) == Array("ARCF".utf8) + [1, 4])
            #expect(saved.dropFirst(6).allSatisfy { $0 == 0 })
        }
    }
}

// MARK: - Error screen

extension CoreSessionTests.DS {
    @Suite struct ErrorScreen {
        @Test func anEncryptedGameFailsAsNotRunnableAndLeavesTheSlotFree() async throws {
            let folder = try SessionFolder()
            let encrypted = try DSVariant.encrypted.file(in: folder)
            let session = EmulationSession(configuration: try folder.dsConfiguration(game: encrypted))

            // melonDS DS accepts the game and would show its error screen instead.
            await #expect(throws: SessionError.gameNotRunnable) {
                _ = try await session.load()
            }

            #expect(session.state == .failed)
            _ = await session.stop()
            #expect(session.state == .stopped)
            #expect(!FileManager.default.fileExists(atPath: folder.batterySave.path(percentEncoded: false)))

            // Game unloaded, core deinitialized, slot released: the next session runs.
            let next = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await next.load()
            let screen = LatestPicture()
            next.connect(video: screen, audio: SoundRecorder())
            await next.runFrames(60)
            #expect(screen.picture?.arm9Frames == 53)
            _ = await next.stop()
        }
    }
}

// MARK: - Import rules against the core

extension CoreSessionTests.DS {
    /// The import check `NDSHeader` and melonDS DS judge the same files alike
    /// (ADR 0006, section 12): what the import accepts, the core loads; what it
    /// refuses as encrypted or for the DSi, the core could only show its error
    /// screen for; what it refuses as no game, the core rejects.
    @Suite struct ImportRules {
        /// What `NDSHeader.check` says about a file.
        enum ImportVerdict: Sendable, Hashable {
            case accepted, tooSmall, tooLarge, notAGame, encryptedGame, needsDSi
            case unexpected(ImportError)

            init(checking data: Data) {
                do throws(ImportError) {
                    try NDSHeader.check(data, fileName: "game.nds")
                    self = .accepted
                } catch {
                    switch error {
                    case .tooSmall: self = .tooSmall
                    case .tooLarge: self = .tooLarge
                    case .notAGame: self = .notAGame
                    case .encryptedGame: self = .encryptedGame
                    case .needsDSi: self = .needsDSi
                    default: self = .unexpected(error)
                    }
                }
            }
        }

        /// What melonDS DS does with a file.
        enum CoreOutcome: Sendable, Hashable {
            /// Loads, and the test program runs: its ARM9 counts frames.
            case runs
            /// Loads without the error screen, but the program does not run.
            case loadsButDoesNotRun
            /// Loads with the error screen: `SessionError.gameNotRunnable`.
            case notRunnable
            /// `retro_load_game` returns false: `SessionError.gameRejected`.
            case rejected
        }

        struct Case: Sendable, CustomTestStringConvertible {
            var variant: DSVariant
            var verdict: ImportVerdict
            var core: CoreOutcome

            var testDescription: String { variant.rawValue }
        }

        static let cases: [Case] = [
            Case(variant: .selftest, verdict: .accepted, core: .runs),
            Case(variant: .encrypted, verdict: .encryptedGame, core: .notRunnable),
            Case(variant: .markerRepeated, verdict: .encryptedGame, core: .notRunnable),
            // melonDS DS loads homebrew without marker and logo checksum. But
            // melonDS "decrypts" the first 2 KiB of every ARM9 binary at
            // 0x4000-0x7FFF on a direct boot; without the marker that fails and
            // leaves 0xE7FFDEFF there. The test program has its entry 16 bytes
            // in, so it cannot run like this; a program laid out like that has
            // to start behind these 2 KiB.
            Case(variant: .homebrew, verdict: .accepted, core: .loadsButDoesNotRun),
            Case(variant: .homebrewWithMarker, verdict: .accepted, core: .runs),
            Case(variant: .homebrewBelow0x4000, verdict: .accepted, core: .runs),
            Case(variant: .withoutLogoChecksum, verdict: .notAGame, core: .rejected),
            Case(variant: .arm9EntryTooHigh, verdict: .notAGame, core: .rejected),
            Case(variant: .arm9BehindTheFile, verdict: .notAGame, core: .rejected),
            Case(variant: .arm9LargerThanTheFile, verdict: .notAGame, core: .rejected),
            // The ARM7 runs zeros, the ARM9 its program.
            Case(variant: .arm7InThePadding, verdict: .accepted, core: .runs),
            // In DS mode melonDS DS refuses only retail titles that need a DSi.
            Case(variant: .dsiOnlyHomebrew, verdict: .accepted, core: .runs),
            Case(variant: .dsiOnlyRetail, verdict: .needsDSi, core: .notRunnable),
            Case(variant: .dsiWareHomebrew, verdict: .accepted, core: .runs),
            Case(variant: .dsiWareRetail, verdict: .needsDSi, core: .notRunnable),
            Case(variant: .dsiEnhanced, verdict: .accepted, core: .runs),
            Case(variant: .tooShort, verdict: .tooSmall, core: .rejected),
        ]

        @Test func everyVariantHasACase() {
            #expect(Set(Self.cases.map(\.variant)) == Set(DSVariant.allCases))
        }

        @Test(arguments: CoreSessionTests.DS.ImportRules.cases)
        func theImportCheckAndTheCoreAgree(_ expected: Case) async throws {
            let folder = try SessionFolder()
            let game = try expected.variant.file(in: folder)

            #expect(ImportVerdict(checking: try Data(contentsOf: game)) == expected.verdict)
            #expect(try await Self.outcome(of: game, in: folder) == expected.core)
        }

        @Test(arguments: [DSVariant.homebrewWithMarker, .homebrewBelow0x4000])
        func homebrewRunsWithoutSaveMemory(_ variant: DSVariant) async throws {
            let folder = try SessionFolder()
            let game = try variant.file(in: folder)
            let session = EmulationSession(configuration: try folder.dsConfiguration(game: game))
            _ = try await session.load()
            let screen = LatestPicture()
            session.connect(video: screen, audio: SoundRecorder())
            await session.runFrames(300)
            let picture = try #require(screen.picture)
            _ = await session.stop()

            #expect(picture.arm9Frames == 293)
            // Only "ARM7 running": a card without save memory answers 0xFF, so
            // nothing reads back, and the boot counter stays at its first value.
            #expect(picture.status == 0x08)
            #expect(picture.bootCounter == 1)
            // melonDS gives homebrew no save memory (SAVE_RAM size 0), so the
            // session never writes a battery save.
            #expect(!FileManager.default.fileExists(atPath: folder.batterySave.path(percentEncoded: false)))
        }

        /// Loads `game` and, if that works, runs 60 frames.
        static func outcome(of game: URL, in folder: SessionFolder) async throws -> CoreOutcome {
            let session = EmulationSession(configuration: try folder.dsConfiguration(game: game))
            var loadError: SessionError?
            do throws(SessionError) {
                _ = try await session.load()
            } catch {
                loadError = error
            }
            switch loadError {
            case nil:
                let screen = LatestPicture()
                session.connect(video: screen, audio: SoundRecorder())
                await session.runFrames(60)
                _ = await session.stop()
                return screen.picture?.arm9Frames == 53 ? .runs : .loadsButDoesNotRun
            case .gameNotRunnable?:
                _ = await session.stop()
                return .notRunnable
            case .gameRejected?:
                _ = await session.stop()
                return .rejected
            case let error?:
                _ = await session.stop()
                throw error
            }
        }
    }
}

// MARK: - Environment

extension CoreSessionTests.DS {
    @Suite struct Environment {
        @Test func melonDSDSIsRefusedExactlyTheTwentyCommandsOfADR0006() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await session.load()
            session.connect(video: PictureRecorder(), audio: SoundRecorder())
            await session.runFrames(300)

            let summary = await session.stop()

            let experimental: UInt32 = 0x10000
            let refused: Set<UInt32> = [
                1, // SET_ROTATION
                18, // SET_SUPPORT_NO_GAME
                21, // SET_FRAME_TIME_CALLBACK
                23, // GET_RUMBLE_INTERFACE
                25 | experimental, // GET_SENSOR_INTERFACE
                33, // SET_PROC_ADDRESS_CALLBACK
                34, // SET_SUBSYSTEM_INFO
                35, // SET_CONTROLLER_INFO
                36 | experimental, // SET_MEMORY_MAPS
                38, // GET_USERNAME
                39, // GET_LANGUAGE
                42 | experimental, // SET_SUPPORT_ACHIEVEMENTS
                45 | experimental, // GET_VFS_INTERFACE
                55, // SET_CORE_OPTIONS_DISPLAY
                59, // GET_MESSAGE_INTERFACE_VERSION
                65, // SET_CONTENT_INFO_OVERRIDE
                69, // SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK
                75 | experimental, // GET_MICROPHONE_INTERFACE
                77 | experimental, // GET_DEVICE_POWER
                78, // SET_NETPACKET_INTERFACE
            ]
            #expect(refused.count == 20)
            #expect(summary.unhandledEnvironmentCommands == refused)
            #expect(summary.framesEmulated == 300)
            // GET_VARIABLE_UPDATE once per frame; the options come the legacy
            // way, SET_VARIABLES once; SET_GEOMETRY once, in the first frame,
            // with the values of the AV info. SET_SYSTEM_AV_INFO never.
            #expect(summary.environmentCalls[17] == 300)
            #expect(summary.environmentCalls[16] == 1)
            #expect(summary.environmentCalls[37] == 1)
            #expect(summary.environmentCalls[32] == nil)
        }
    }
}

// MARK: - Firmware

extension CoreSessionTests.DS {
    /// The Wi-Fi settings of melonDS's generated firmware, which melonDS DS
    /// keeps in `System/melonDS DS/wfcsettings.bin` (ADR 0006).
    @Suite struct Firmware {
        /// Where the three access points of 256 bytes start in the file. Before
        /// them lie the three extended access points of 512 bytes of the DSi,
        /// which the generated DS firmware leaves erased with 0xFF
        /// (`SPI_Firmware.cpp` of melonDS).
        static let accessPoints = [1536, 1792, 2048]

        /// The primary DNS server of an access point at 0xC8, the secondary
        /// one at 0xCC.
        static func dnsServers(ofAccessPointAt start: Int) -> Range<Int> {
            start + 0xC8 ..< start + 0xD0
        }

        @Test func theWiFiSettingsNameNoDNSServerAndForgetTheOneOfAnEarlierSession() async throws {
            #expect(GameSystem.ds.coreOptions["melonds_firmware_wfc_dns"] == "0.0.0.0")
            let folder = try SessionFolder()
            let settings = folder.systemDirectory.appending(path: "melonDS DS/wfcsettings.bin")
            let accessPoint0 = Self.dnsServers(ofAccessPointAt: Self.accessPoints[0])

            // With the core's default, as before Arcfold set the option, access
            // point 0 names a replacement server for the discontinued online
            // service, as primary and as secondary DNS server.
            var coreDefault = try folder.dsConfiguration()
            coreDefault.coreOptions["melonds_firmware_wfc_dns"] = nil
            try await Self.runOneSecond(coreDefault)
            let before = try Data(contentsOf: settings)
            #expect(before.count == 2304)
            let server = Array(before[accessPoint0].prefix(4))
            #expect(server != [0, 0, 0, 0])
            #expect(Array(before[accessPoint0]) == server + server)

            // The next session with the app's options clears it: no access
            // point names a DNS server, and the address is nowhere in the file.
            try await Self.runOneSecond(try folder.dsConfiguration())
            let after = try Data(contentsOf: settings)
            #expect(after.count == 2304)
            for start in Self.accessPoints {
                #expect(after[Self.dnsServers(ofAccessPointAt: start)].allSatisfy { $0 == 0 }, "access point at \(start)")
            }
            #expect(after.range(of: Data(server)) == nil, "wfcsettings.bin still holds \(server)")
        }

        /// Loads `selftest.nds`, runs 60 frames and stops; the core writes the
        /// Wi-Fi settings when it unloads.
        private static func runOneSecond(_ configuration: SessionConfiguration) async throws {
            let session = EmulationSession(configuration: configuration)
            _ = try await session.load()
            session.connect(video: LatestPicture(), audio: SoundRecorder())
            await session.runFrames(60)
            _ = await session.stop()
        }
    }
}

// MARK: - Lifecycle with the real clock

extension CoreSessionTests.DS {
    @Suite struct Lifecycle {
        @Test func loadRunPauseResumeStopInRealTime() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration(pacing: .realTime))
            let info = try await session.load()
            let pictures = PictureRecorder()
            // 35 ms at the DS rate, the lowest target level of ADR 0005.
            let sound = ClockedSoundSink(
                sampleRate: info.timing.sampleRate, targetFrames: Int((info.timing.sampleRate * 0.035).rounded(.up))
            )
            session.connect(video: pictures, audio: sound)

            session.resume()
            try await waitUntil { pictures.count >= 120 }
            #expect(session.state == .running)
            // Like the app: first the sound, then the emulation.
            sound.suspend()
            await session.pause()
            #expect(session.state == .paused)
            let pausedAt = pictures.count
            #expect(session.stats.snapshot().framesEmulated == UInt64(pausedAt))
            try await Task.sleep(for: .milliseconds(300))
            #expect(pictures.count == pausedAt)
            #expect(FileManager.default.fileExists(atPath: folder.batterySave.path(percentEncoded: false)))

            session.resume()
            try await waitUntil { pictures.count >= pausedAt + 60 }
            let summary = await session.stop()
            #expect(session.state == .stopped)
            #expect(summary.framesEmulated >= UInt64(pausedAt + 60))
            #expect(sound.underruns == 0)
            #expect(try Data(contentsOf: folder.batterySave).count == 8192)

            // Plausibility only: the Simulator runs on the Mac's chip.
            let arrivals = pictures.arrivals
            let ticks = Double(arrivals[119] - arrivals[9])
            let rate = 110 / (ticks * CoreSessionTests.Lifecycle.secondsPerTick)
            #expect(abs(rate - 59.83) <= 1, "\(rate) frames per second")
        }
    }
}

// MARK: - Performance

extension CoreSessionTests.DS {
    @Suite struct Performance {
        /// A plausibility value from the Simulator, which runs on the Mac's
        /// chip; only the Duo counts (ADR 0006, section 14). The test prints
        /// median and maximum and fails only far outside the frame budget.
        @Test func retroRunOfTheTestProgramStaysFarInsideTheFrameBudget() async throws {
            let folder = try SessionFolder()
            let session = EmulationSession(configuration: try folder.dsConfiguration())
            _ = try await session.load()
            session.connect(video: LatestPicture(), audio: SoundRecorder())
            await session.runFrames(60)

            var times: [Duration] = []
            for _ in 0..<600 {
                await session.runFrames(1)
                times.append(session.stats.snapshot().lastRunTime)
            }
            _ = await session.stop()

            times.sort()
            let median = times[times.count / 2]
            let maximum = try #require(times.last)
            func milliseconds(_ duration: Duration) -> String {
                let (seconds, attoseconds) = duration.components
                return String(format: "%.2f ms", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
            }
            print("melonDS DS, selftest.nds, retro_run over 600 frames: median \(milliseconds(median)), maximum \(milliseconds(maximum))")
            #expect(median < .milliseconds(16), "median \(milliseconds(median))")
        }
    }
}
