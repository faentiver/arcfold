@testable import Arcfold
import FoldLayout
import Foundation
import SwiftUI
import Testing

/// The pause reasons of `PlaySession` with a fed sequence of hinge states and
/// scene phases (ADR 0006, section 10). No core runs: the session stays idle,
/// so only its reasons change, which the queued steps then apply.
@MainActor
struct PauseTests {
    static func session() -> PlaySession {
        let location = LibraryLocation(root: FileManager.default.temporaryDirectory
            .appending(path: "PauseTests-\(UUID().uuidString)", directoryHint: .isDirectory))
        let game = Game(id: "pause-test", name: "Pause test", system: "ds", originalFileName: "pause.nds",
                        size: 0, importedAt: .now)
        return PlaySession(game: game, files: location.files(for: game), location: location)
    }

    /// Polls `condition` until it holds or `timeout` passes.
    static func eventually(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: timeout)
        while clock.now < end {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test func closingPausesAsFoldedAndOpeningResumes() async {
        let session = Self.session()
        // onHingeChange reports the state when the view appears: no closing.
        session.hingeChanged(from: nil, to: .closed)
        await session.settle()
        #expect(!session.isFolded && !session.isPaused)
        // Opening a device that was closed before the game: nothing to resume.
        session.hingeChanged(from: .closed, to: .fullyOpen)
        #expect(!session.isFolded && !session.isPaused)

        session.hingeChanged(from: .fullyOpen, to: .closed)
        await session.settle()
        #expect(session.isFolded && session.isPaused && session.showsPauseMenu)
        #expect(!session.isUserPaused, "Its own reason, not a pause by hand")

        session.hingeChanged(from: .closed, to: .partiallyOpen)
        await session.settle()
        #expect(!session.isFolded && !session.isPaused && !session.showsPauseMenu)

        // From partially open as well.
        session.hingeChanged(from: .partiallyOpen, to: .closed)
        #expect(session.isFolded)
        session.hingeChanged(from: .closed, to: .fullyOpen)
        #expect(!session.isFolded)
    }

    @Test func halfAndFullyOpenNeverPause() async {
        let session = Self.session()
        session.hingeChanged(from: nil, to: .fullyOpen)
        for (old, new) in [(HingeState.fullyOpen, HingeState.partiallyOpen), (.partiallyOpen, .fullyOpen),
                           (.fullyOpen, .partiallyOpen), (.partiallyOpen, .partiallyOpen)] {
            session.hingeChanged(from: old, to: new)
            await session.settle()
            #expect(!session.isPaused, "\(old) → \(new)")
        }
    }

    @Test func anotherReasonKeepsTheGamePausedWhenOpened() async {
        let session = Self.session()
        session.setUserPaused(true)
        session.hingeChanged(from: .fullyOpen, to: .closed)
        await session.settle()
        #expect(session.isUserPaused && session.isFolded)
        session.hingeChanged(from: .closed, to: .fullyOpen)
        await session.settle()
        #expect(!session.isFolded)
        #expect(session.isPaused && session.showsPauseMenu, "Still paused by hand")
    }

    /// "Resume" on the outer display plays on while the device stays closed;
    /// opening it later changes nothing.
    @Test func resumingWhileClosedClearsTheReason() async {
        let session = Self.session()
        session.hingeChanged(from: .fullyOpen, to: .closed)
        session.resumeFromMenu()
        await session.settle()
        #expect(!session.isPaused && !session.showsPauseMenu)
        session.hingeChanged(from: .closed, to: .fullyOpen)
        await session.settle()
        #expect(!session.isPaused)
    }

    /// Without hinge information the reason cannot stay.
    @Test func losingTheHingeClearsTheReason() async {
        let session = Self.session()
        session.hingeChanged(from: .fullyOpen, to: .closed)
        session.hingeChanged(from: .closed, to: nil)
        await session.settle()
        #expect(!session.isFolded)
        session.hingeChanged(from: nil, to: nil)
        #expect(!session.isPaused)
    }

    @Test func inactivePausesOnlyAfter300Milliseconds() async throws {
        let session = Self.session()
        session.scenePhaseChanged(to: .inactive)
        try await Task.sleep(for: .milliseconds(150))
        await session.settle()
        #expect(!session.isScenePaused, "Not yet after 150 ms")
        #expect(try await Self.eventually { session.isScenePaused }, "Paused after 300 ms")
        session.scenePhaseChanged(to: .active)
        await session.settle()
        #expect(!session.isScenePaused)
    }

    /// A pose change may pass through `.inactive`: back to `.active` within
    /// 300 ms, the game never stops.
    @Test func activeWithin300MillisecondsKeepsTheGameRunning() async throws {
        let session = Self.session()
        session.scenePhaseChanged(to: .inactive)
        try await Task.sleep(for: .milliseconds(100))
        session.scenePhaseChanged(to: .active)
        try await Task.sleep(for: .milliseconds(600))
        await session.settle()
        #expect(!session.isScenePaused && !session.isPaused)
    }

    @Test func backgroundPausesAtOnce() async {
        let session = Self.session()
        session.scenePhaseChanged(to: .inactive)
        session.scenePhaseChanged(to: .background)
        await session.settle()
        #expect(session.isScenePaused)
        session.scenePhaseChanged(to: .inactive)
        session.scenePhaseChanged(to: .active)
        await session.settle()
        #expect(!session.isScenePaused)
    }
}

#if DEBUG
/// The artificial folds of `-ArcfoldFoldOverride` (ADR 0006, section 15).
@MainActor
struct FoldOverrideTests {
    static let inner = FoldGeometry(container: PixelSize(width: 2007, height: 2853))
    static let innerSideways = FoldGeometry(container: PixelSize(width: 2853, height: 2007))

    @Test func flatTabletopAndBook() {
        let flat = FoldOverride.flat.applied(to: Self.inner)
        #expect(flat.fold == PixelRect(x: 0, y: 1426, width: 2007, height: 0) && !flat.isFoldActive)
        #expect(flat.posture == .flat)
        let flatSideways = FoldOverride.flat.applied(to: Self.innerSideways)
        #expect(flatSideways.fold == PixelRect(x: 1426, y: 0, width: 0, height: 2007))
        let tabletop = FoldOverride.tabletop.applied(to: Self.inner)
        #expect(tabletop.fold == PixelRect(x: 0, y: 1402, width: 2007, height: 48) && tabletop.isFoldActive)
        #expect(tabletop.posture == .tabletop)
        let book = FoldOverride.book.applied(to: Self.innerSideways)
        #expect(book.fold == PixelRect(x: 1402, y: 0, width: 48, height: 2007) && book.posture == .flat)
        // The DS in the override's tabletop: 6× above the fold with the rim
        // of the console, 4× below it between pad and face buttons; 7× with
        // a controller as in ADR 0006.
        #expect(GameLayout(system: .ds, geometry: tabletop, showsTouchControls: true).screens.map(\.scale) == [6, 4])
        #expect(GameLayout(system: .ds, geometry: tabletop, showsTouchControls: false).screens.map(\.scale) == [7, 7])
    }
}
#endif
