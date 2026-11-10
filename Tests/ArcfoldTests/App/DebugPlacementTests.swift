@testable import Arcfold
import CoreGraphics
import FoldLayout
import Foundation
import LibretroKit
import Renderer
import SwiftUI
import Testing
import UIKit

/// The debug overlay (ADR 0007) in every geometry of `DuoGeometries` and the
/// closed Duo sideways as measured, for the GBA and the DS, with touch
/// controls and with a controller: its area lies in the safe area and covers
/// no button with its slop, no reach of the pad, no pause button, no touch
/// screen and no fold, and it holds the card with every line at one of the
/// card's type sizes. While the status chip or a notice shows, the area
/// ends 6 pt from their stack at every size of the text, and the card shows
/// the lines that fit it.
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

    /// `area` lies in the safe area and covers nothing that takes touches,
    /// no touch screen and no fold.
    static func checkCoversNothing(_ area: CGRect, in testCase: Case) {
        let placement = testCase.placement
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

    @Test(arguments: NoticePlacementTests.cases)
    func theDebugOverlayCoversNoButton(_ testCase: Case) {
        Self.checkCoversNothing(testCase.placement.debugArea, in: testCase)
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

    // MARK: Beside the status chip and a notice

    /// What the stack of the notices shows: the chip, the longest notice, or
    /// both.
    static let stacks: [(name: String, notice: String?, chip: String?)] = [
        ("the chip", nil, NoticePlacementTests.audioProblem),
        ("a notice", NoticePlacementTests.longNotice, nil),
        ("the chip above a notice", NoticePlacementTests.longNotice, NoticePlacementTests.audioProblem),
    ]

    /// The heights of the stack measured so far: many geometries share a
    /// column, and SwiftUI lays the stack out anew for each measurement.
    @MainActor private static var measuredHeights: [String: CGFloat] = [:]

    /// The height of stack `index` of `stacks` as SwiftUI lays it out in
    /// `column` at `size`.
    @MainActor static func stackHeight(_ index: Int, in column: CGRect, size: DynamicTypeSize) -> CGFloat {
        let key = "\(index) \(column.width) \(column.height) \(size)"
        if let height = measuredHeights[key] {
            return height
        }
        let height = NoticePlacementTests.stackHeight(width: column.width, offering: column.height, notice: stacks[index].notice,
                                                      audioProblem: stacks[index].chip, size: size)
        measuredHeights[key] = height
        return height
    }

    /// The card and the stack never meet: for the chip, a notice and both,
    /// at every size of the text, the area of the card keeps 6 pt from what
    /// the stack takes of its column, and still covers nothing else.
    @MainActor @Test(arguments: NoticePlacementTests.cases)
    func theDebugOverlayGivesWayToTheChipAndANotice(_ testCase: Case) {
        let placement = testCase.placement
        for size in DynamicTypeSize.allCases {
            for (index, stack) in Self.stacks.enumerated() {
                let height = Self.stackHeight(index, in: placement.noticeColumn, size: size)
                let taken = placement.noticeStack(height: height)
                let area = placement.debugArea(besideStackOf: height)
                let apart = taken.insetBy(dx: -OverlayPlacement.spacing + 0.001, dy: -OverlayPlacement.spacing + 0.001)
                #expect(area.isEmpty || !area.intersects(apart),
                        "\(size), \(stack.name): the debug overlay \(area) meets the stack \(taken)")
                #expect(placement.noticeColumn.insetBy(dx: -0.001, dy: -0.001).contains(taken))
                // The card stays where it is and only gives up room, never
                // down to a strip too narrow to read.
                #expect(placement.debugArea.contains(area), "\(size), \(stack.name): \(area) leaves \(placement.debugArea)")
                #expect(area.isEmpty || area.width >= OverlayPlacement.debugMinWidth, "\(size), \(stack.name): \(area)")
                Self.checkCoversNothing(area, in: testCase)
            }
        }
    }

    /// Without the chip and a notice the card keeps its usual area.
    @Test(arguments: NoticePlacementTests.cases)
    func withoutAStackTheDebugOverlayKeepsItsArea(_ testCase: Case) {
        let placement = testCase.placement
        #expect(placement.debugArea(besideStackOf: 0) == placement.debugArea)
        #expect(placement.noticeStack(height: 0).isEmpty)
        // A stack is never higher than its column.
        #expect(placement.noticeStack(height: .greatestFiniteMagnitude) == placement.noticeColumn)
    }

    /// The fault found in the real poses stays fixed. Sideways on the outer
    /// display the DS has room for both only on its upper screen, where the
    /// chip and a notice lay on the card at the default size: now the card
    /// ends above them, and beside the chip alone it still shows every line.
    /// Upright on the outer display and flat upright on the inner one they
    /// met with large text.
    @MainActor @Test func theCardEndsAboveTheStackOnTheUpperScreenOfTheDS() throws {
        let flatUpright = DuoGeometries.Case(name: "flat upright as measured", geometry: FoldGeometry(
            container: DuoGeometries.inner, fold: PixelRect(x: 0, y: 1366, width: 2007, height: 121), isFoldActive: false))
        let closed = DuoGeometries.Case(name: "closed", geometry: DuoGeometries.closed(barOnTop: false))
        for (geometry, size) in [(NoticePlacementTests.measuredSideways, DynamicTypeSize.large),
                                 (closed, .accessibility5), (flatUpright, .accessibility5)] {
            let testCase = Case(system: .ds, geometry: geometry, showsControls: true)
            let placement = testCase.placement
            let both = Self.stackHeight(2, in: placement.noticeColumn, size: size)
            let taken = placement.noticeStack(height: both)
            #expect(placement.debugArea.intersects(taken), "\(geometry.name): the usual area lies where the stack does")
            let area = placement.debugArea(besideStackOf: both)
            #expect(area.isEmpty || area.maxY <= taken.minY - OverlayPlacement.spacing + 0.001,
                    "\(geometry.name): \(area) does not end above \(taken)")

            // Beside the chip alone, which stays, the card keeps every line.
            let chip = Self.stackHeight(0, in: placement.noticeColumn, size: .large)
            let beside = placement.debugArea(besideStackOf: chip)
            let lines = Self.lines(for: testCase)
            let heights = DebugOverlay.fontSizes.map { DebugOverlay.estimatedHeight(of: lines, width: beside.width, fontSize: $0) }
            #expect(heights.contains { $0 <= beside.height },
                    "\(geometry.name): beside the chip the card needs \(heights) pt in \(beside.width) × \(beside.height) pt")
        }
    }

    /// The height of the card as SwiftUI lays it out in an area of `size`.
    @MainActor static func cardHeight(_ readings: DebugReadings, in size: CGSize) -> CGFloat {
        let card = DebugOverlay { readings }
            .frame(width: size.width, alignment: .topLeading)
        return UIHostingController(rootView: card).sizeThatFits(in: size).height
    }

    /// The card never leaves the area it is offered: it takes a smaller
    /// type, then leaves out lines from the end, whole, and where not even
    /// one line fits it draws nothing. With more room it never shows less.
    @MainActor @Test func theCardShowsTheLinesThatFit() {
        let testCase = Case(system: .ds, geometry: NoticePlacementTests.measuredSideways, showsControls: true)
        var readings = GlassGallery.readings
        readings.fold = FoldReadings(geometry: testCase.geometry.geometry, layout: testCase.layout, isOverridden: false)
        let lines = readings.lines
        let width = testCase.placement.debugArea.width
        let smallest = DebugOverlay.fontSizes[DebugOverlay.fontSizes.count - 1]
        let oneLine = DebugOverlay.estimatedHeight(of: [lines[0]], width: width, fontSize: smallest)
        let everyLine = DebugOverlay.estimatedHeight(of: lines, width: width, fontSize: smallest)
        // The most a line adds to the card: its rows and the spacing.
        let highestLine = lines.map { DebugOverlay.estimatedHeight(of: [$0], width: width, fontSize: smallest) }.max() ?? 0

        #expect(Self.cardHeight(readings, in: CGSize(width: width, height: 0)) <= 1)
        var previous: CGFloat = 0
        var heights: Set<CGFloat> = []
        for offered in stride(from: 4, through: 400, by: 4) {
            let height = Self.cardHeight(readings, in: CGSize(width: width, height: CGFloat(offered)))
            #expect(height <= max(CGFloat(offered), 1) + 0.5, "\(height) pt in \(offered) pt")
            #expect(height >= previous, "less with more room: \(height) pt in \(offered) pt after \(previous) pt")
            if CGFloat(offered) >= oneLine {
                #expect(height > 1, "no line in \(offered) pt")
            }
            if CGFloat(offered) >= oneLine, CGFloat(offered) <= everyLine {
                #expect(height >= CGFloat(offered) - highestLine, "a line more fits: \(height) pt in \(offered) pt")
            }
            previous = height
            heights.insert(height.rounded())
        }
        // Nothing, the lines one by one at the smallest type, and every line
        // at each of the type sizes.
        #expect(heights.count >= lines.count + DebugOverlay.fontSizes.count - 1, "\(heights.sorted())")
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
