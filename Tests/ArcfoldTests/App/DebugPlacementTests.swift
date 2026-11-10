@testable import Arcfold
import CoreGraphics
import FoldLayout
import Foundation
import LibretroKit
import Renderer
import Testing

/// The debug overlay (ADR 0007) in every geometry of `DuoGeometries` and the
/// closed Duo sideways as measured, for the GBA and the DS, with touch
/// controls and with a controller: its area lies in the safe area and covers
/// no button with its slop, no reach of the pad, no pause button, no touch
/// screen and no fold, and it holds the card with every line at one of the
/// card's type sizes.
struct DebugPlacementTests {
    typealias Case = OverlayPlacementTests.Case

    /// The readings of a running game with the longest lines seen in the
    /// Simulator: late frames, an occlusion, both screens, the pointer.
    static func lines(for testCase: Case) -> [String] {
        var readings = DebugReadings(
            emulation: SessionStats.Snapshot(
                framesEmulated: 123_584, framesPerSecond: 59.97, lateFrames: 308, resyncs: 12,
                lastRunTime: .microseconds(3900), maxRunTime: .microseconds(16_180),
                maxLateness: .microseconds(800), periodTrim: -0.00012),
            presentation: PresentationStats.Snapshot(
                displayUpdates: 72_000, refreshRate: 120, framesShown: 35_830, framesRepeated: 36_170,
                framesSkipped: 114, lateSelections: 3, gpuBusy: 1),
            mailbox: MailboxCounters(published: 123_584, overwritten: 12),
            audio: AudioCounters(
                underruns: 2, underrunFrames: 512, droppedFrames: 128, primes: 3, renderCalls: 120_000,
                largestRequest: 164, bufferedFrames: 1130, targetFrames: 1147),
            audioSampleRate: 32768,
            route: AudioRoute(hardwareSampleRate: 48000, ioBufferDuration: 0.0053, outputLatency: 0.012),
            input: InputReadings(held: [.a, .b, .right, .up, .l, .r], lastPressed: .select, presses: 1234),
            pointer: testCase.system.screens.touchScreen.map { index in
                PointerReadings(
                    held: PointerPosition(pixelX: 255, pixelY: 383, frameWidth: 256, frameHeight: 384),
                    lastPress: PointerPosition(pixelX: 128, pixelY: 288, frameWidth: 256, frameHeight: 384),
                    presses: 123, frameSize: testCase.system.screens.frameSize,
                    touchScreen: testCase.system.screens.sources[index])
            },
            thermalState: .nominal,
            isLowPowerModeEnabled: false)
        var geometry = testCase.geometry.geometry
        if geometry.occlusions.isEmpty {
            geometry.occlusions = [PixelRect(x: 87, y: 87, width: 112, height: 112), PixelRect(x: 0, y: 0, width: 252, height: 246)]
        }
        readings.fold = FoldReadings(geometry: geometry, layout: testCase.layout, isOverridden: true)
        readings.isPaused = true
        readings.pauses = 12
        return readings.lines
    }

    @Test(arguments: NoticePlacementTests.cases)
    func theDebugOverlayCoversNoButton(_ testCase: Case) {
        let placement = testCase.placement
        let area = placement.debugArea
        let safe = testCase.points(testCase.geometry.geometry.safeBounds)
        #expect(safe.insetBy(dx: placement.inset - 0.001, dy: placement.inset - 0.001).contains(area),
                "\(area) leaves the safe area \(safe)")
        for (label, button) in OverlayPlacementTests.buttonAreas(testCase.controls) {
            #expect(!area.intersects(button), "the debug overlay covers \(label): \(area) ∩ \(button)")
        }
        if let pad = testCase.controls?.pad {
            #expect(!OverlayPlacementTests.intersects(area, circle: pad.center, radius: pad.radius * TouchLayout.padReach),
                    "the debug overlay covers the pad")
        }
        if let target = placement.pauseTarget {
            #expect(!area.intersects(target), "the debug overlay covers the pause button \(target)")
        }
        if let touch = testCase.layout.touchScreen {
            #expect(!area.intersects(testCase.points(touch.destination)), "the debug overlay lies on the touch screen")
        }
        if let fold = testCase.geometry.geometry.fold, !fold.isEmpty {
            #expect(!area.intersects(testCase.points(fold)), "the debug overlay lies on the fold \(fold)")
        }
    }

    /// The card shows every line: at one of its type sizes the lines of a
    /// running game fit the area, wrapped at words.
    @Test(arguments: NoticePlacementTests.cases)
    func theDebugOverlayShowsEveryLine(_ testCase: Case) {
        let area = testCase.placement.debugArea
        let lines = Self.lines(for: testCase)
        let heights = DebugOverlay.fontSizes.map { DebugOverlay.estimatedHeight(of: lines, width: area.width, fontSize: $0) }
        #expect(heights.contains { $0 <= area.height },
                "the card needs \(heights) pt at its sizes in an area of \(area.width) × \(area.height) pt")
    }

    /// The faults found in the real poses stay fixed: sideways on the outer
    /// display the card lay on L, R and X of the DS and on L, R and A of the
    /// GBA, open and in the book pose on L of the GBA.
    @Test func theCardStaysBetweenTheShoulderButtons() throws {
        for system in [GameSystem.ds, .gba] {
            let sideways = Case(system: system, geometry: NoticePlacementTests.measuredSideways, showsControls: true)
            let area = sideways.placement.debugArea
            let buttons = OverlayPlacementTests.buttonAreas(sideways.controls)
            let l = try #require(buttons.first { $0.0 == "L" }).1
            let r = try #require(buttons.first { $0.0 == "R" }).1
            #expect(area.minX >= l.maxX && area.maxX <= r.minX, "\(system.name): \(area) between \(l) and \(r)")
        }
        let book = DuoGeometries.Case(name: "book", geometry: FoldGeometry(
            container: DuoGeometries.innerLandscape, fold: PixelRect(x: 1366, y: 0, width: 121, height: 2007),
            isFoldActive: true))
        let gba = Case(system: .gba, geometry: book, showsControls: true)
        let l = try #require(OverlayPlacementTests.buttonAreas(gba.controls).first { $0.0 == "L" }).1
        #expect(!gba.placement.debugArea.intersects(l))
    }

    @Test func theEstimateWrapsAtWords() {
        // 19 columns at 10 pt: (132 - 12) / 6.02; a line is 12 pt high, the
        // card adds 2 pt between the lines and 6 pt around them.
        func height(_ lines: [String]) -> Double {
            Double(DebugOverlay.estimatedHeight(of: lines, width: 132, fontSize: 10))
        }
        #expect(height(["one"]) == 24.0)
        #expect(height(["one two three four five six"]) == 36.0)
        #expect(height(["one", "two"]) == 38.0)
        #expect(height([String(repeating: "x", count: 45)]) == 48.0)
    }
}
