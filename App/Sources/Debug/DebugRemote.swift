#if DEBUG
import FoldLayout
import Foundation
import LibretroKit
import notify
import Observation
import os

/// Remote control of a running game in debug builds, for acceptance runs and
/// UI tests in the Simulator, where only Device Hub or the posture tool of
/// Scripts/pose-check.sh change the real pose, both from outside the app
/// (ADR 0006, section 15). It listens for Darwin notifications, which a
/// script posts with `xcrun simctl spawn <UDID> notifyutil -p <name>` and a
/// UI test with `notify_post`:
///
/// - `com.faentiver.arcfold.debug.fold.flat`, `….tabletop` and `….book`
///   replace the measured fold the way `-ArcfoldFoldOverride` does;
///   `com.faentiver.arcfold.debug.fold.measured` goes back to the measured one.
/// - `com.faentiver.arcfold.debug.hinge.closed` and `….open` hand a hinge
///   change to the game the way `onHingeChange` does: closing pauses it with
///   the pause menu, opening resumes a game that closing paused.
/// - `com.faentiver.arcfold.debug.overlay.hide` and `….show` hide the debug
///   overlay and bring it back, so that a screenshot shows the whole picture.
/// - `com.faentiver.arcfold.debug.keys.hold` holds a few buttons down as
///   if fingers lay on them (up, A, L and Select), `….keys.release` lets
///   them go: a screenshot then shows pressed keys, and the game sees them.
///
/// None of it moves the app to another display or changes the size of its
/// view; that stays with the pose check (Scripts/pose-check.sh). Every change
/// goes to the log (category `fold`), marked as simulated.
@Observable
final class DebugRemote {
    /// A hinge change that did not come from the hinge, numbered so that two
    /// equal changes in a row are two changes.
    struct HingeChange: Equatable {
        var old: HingeState?
        var new: HingeState?
        var number: Int
    }

    /// Something the running game shows on request, so that acceptance runs
    /// and UI tests see it in every pose: `….debug.notice.long` shows the
    /// longest notice the app knows, a failed battery save with its reason,
    /// through the session's own path; `….debug.chip.show` and `….chip.hide`
    /// set and clear the status chip of a missing audio output.
    enum Sample: Equatable {
        case longNotice
        case audioProblem(shown: Bool)
    }

    /// A sample request, numbered like a hinge change.
    struct SampleRequest: Equatable {
        var sample: Sample
        var number: Int
    }

    /// What a notification asks for.
    private enum Action {
        case fold(FoldOverride?)
        case hinge(HingeState)
        case overlay(hidden: Bool)
        case sample(Sample)
        case keys(JoypadButtons)
    }

    static let shared = DebugRemote()
    /// The common start of the notification names.
    static let prefix = "com.faentiver.arcfold.debug."

    private static let actions: [(name: String, action: Action)] = [
        ("fold.measured", .fold(nil)),
        ("fold.flat", .fold(.flat)),
        ("fold.tabletop", .fold(.tabletop)),
        ("fold.book", .fold(.book)),
        ("hinge.closed", .hinge(.closed)),
        ("hinge.open", .hinge(.fullyOpen)),
        ("overlay.hide", .overlay(hidden: true)),
        ("overlay.show", .overlay(hidden: false)),
        ("notice.long", .sample(.longNotice)),
        ("chip.show", .sample(.audioProblem(shown: true))),
        ("chip.hide", .sample(.audioProblem(shown: false))),
        ("keys.hold", .keys([.up, .a, .l, .select])),
        ("keys.release", .keys([])),
    ]

    private static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "fold")

    /// Replaces the measured fold; begins with `-ArcfoldFoldOverride`.
    private(set) var foldOverride: FoldOverride? = DebugLaunch.foldOverride
    /// The latest simulated hinge change, for the game view.
    private(set) var hingeChange: HingeChange?
    /// The debug overlay stays hidden, whatever the game menu says.
    private(set) var hidesOverlay = false
    /// The latest sample request, for the game view.
    private(set) var sampleRequest: SampleRequest?
    /// Buttons the game view holds down as if fingers lay on them.
    private(set) var heldButtons: JoypadButtons = []
    /// The hinge as the game saw it last, real or simulated.
    @ObservationIgnored private var hinge: HingeState?
    @ObservationIgnored private var changes = 0
    @ObservationIgnored private var tokens: [Int32] = []

    private init() {
        for (name, action) in Self.actions {
            var token: Int32 = 0
            // Delivered on the main queue, so the handler is on the main actor.
            let status = notify_register_dispatch(Self.prefix + name, &token, .main) { @Sendable [weak self] _ in
                MainActor.assumeIsolated {
                    self?.perform(action, name: name)
                }
            }
            if status == 0 {
                tokens.append(token)
            } else {
                Self.logger.error("Could not listen for \(Self.prefix + name, privacy: .public): \(status)")
            }
        }
    }

    /// The real hinge reported a state; simulated changes start from it.
    func noteHinge(_ state: HingeState?) {
        hinge = state
    }

    private func perform(_ action: Action, name: String) {
        switch action {
        case let .fold(override):
            foldOverride = override
            Self.logger.notice("Simulated fold: \(override?.rawValue ?? "measured", privacy: .public) (\(name, privacy: .public))")
        case let .hinge(state):
            let old = hinge
            hinge = state
            changes += 1
            hingeChange = HingeChange(old: old, new: state, number: changes)
            Self.logger.notice("Simulated hinge: \(Self.name(of: old), privacy: .public) → \(Self.name(of: state), privacy: .public)")
        case let .overlay(hidden):
            hidesOverlay = hidden
            Self.logger.notice("Debug overlay \(hidden ? "hidden" : "shown", privacy: .public) by notification")
        case let .sample(sample):
            changes += 1
            sampleRequest = SampleRequest(sample: sample, number: changes)
            Self.logger.notice("Sample \(name, privacy: .public) by notification")
        case let .keys(buttons):
            heldButtons = buttons
            Self.logger.notice("Held buttons \(buttons.rawValue, privacy: .public) by notification (\(name, privacy: .public))")
        }
    }

    private static func name(of state: HingeState?) -> String {
        switch state {
        case .closed?: "closed"
        case .partiallyOpen?: "partially open"
        case .fullyOpen?: "fully open"
        case nil: "none"
        }
    }
}
#endif
