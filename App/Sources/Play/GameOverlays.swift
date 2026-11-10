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

    /// The height of the status chip and the notice as laid out, 0 while
    /// neither shows: the debug overlay gives way to them.
    @State private var noticeStackHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let debugReadings {
                // In the free area OverlayPlacement names, clear of the chip
                // and a notice while they show: the card wraps its lines to
                // the width and never reaches a button, the pad or the touch
                // screen; lines that do not fit even in its smallest type
                // are left out rather than laid over a control or a notice.
                let area = placement.debugArea(besideStackOf: noticeStackHeight)
                DebugOverlay(read: debugReadings)
                    .frame(width: area.width, height: area.height, alignment: .topLeading)
                    .clipped()
                    .offset(x: area.minX, y: area.minY)
                    .allowsHitTesting(false)
            }

            // On the picture, clear of every button, the touch screen and the
            // fold, and without hit testing, so neither ever takes a touch
            // meant for the game (rule R6; M1 fault).
            NoticeStack(audioProblem: audioProblem, notice: notice)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    noticeStackHeight = height
                }
                .frame(width: placement.noticeColumn.width, height: placement.noticeColumn.height, alignment: .bottom)
                .position(x: placement.noticeColumn.midX, y: placement.noticeColumn.midY)

            if let failure {
                GameFailureView(message: failure, area: placement.failureArea, close: close)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
