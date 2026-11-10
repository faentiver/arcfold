import SwiftUI

/// What lies over a running game, where `OverlayPlacement` puts it in the
/// coordinates of `GameStage`: the debug overlay, the status chip, notices
/// and the failure message. The pause button belongs to the stage, above
/// its touch surface. It takes plain values, so `GameView` keeps one call
/// and the debug gallery shows the same overlays without a session (ADR 0007).
struct GameOverlays: View {
    let placement: OverlayPlacement
    /// The readings of the debug overlay; nil hides it.
    let debugReadings: (() -> DebugReadings)?
    /// A problem that stays, such as a missing audio output.
    let audioProblem: String?
    let notice: String?
    /// Why the game could not start; shown instead of the game.
    let failure: String?
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let debugReadings {
                DebugOverlay(read: debugReadings)
                    // The lines wrap before they reach a pause button beside them.
                    .frame(maxWidth: placement.debugMaxWidth, alignment: .leading)
                    .offset(x: placement.debugOrigin.x, y: placement.debugOrigin.y)
                    // Over the controls in some poses; it must not take their
                    // touches (rule R6).
                    .allowsHitTesting(false)
            }

            // On the picture, clear of every button, the touch screen and the
            // fold, and without hit testing, so neither ever takes a touch
            // meant for the game (rule R6; M1 fault).
            NoticeStack(audioProblem: audioProblem, notice: notice)
                .frame(width: placement.noticeColumn.width, height: placement.noticeColumn.height, alignment: .bottom)
                .position(x: placement.noticeColumn.midX, y: placement.noticeColumn.midY)

            if let failure {
                GameFailureView(message: failure, area: placement.failureArea, close: close)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
