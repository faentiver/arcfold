#if DEBUG
import Renderer
import SwiftUI

/// The game screen with a test pattern instead of a core, for checking the
/// picture path (mailbox, display link, shader) in the Simulator. Opened by
/// the launch argument `-ArcfoldTestPattern YES` in debug builds; a double
/// tap closes it.
struct TestPatternView: View {
    @State private var mailbox = PreviewContent.mailboxWithTestPattern()
    @State private var stats = PresentationStats()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let snapshot = stats.snapshot()
                Text(verbatim: "Test pattern · \(Int(snapshot.refreshRate.rounded())) Hz · shown \(snapshot.framesShown)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .padding(8)
                    .accessibilityIdentifier("test-pattern-stats")
            }
            GameScreen(mailbox: mailbox, stats: stats)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Test pattern"))
                .accessibilityIdentifier("test-pattern-screen")
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .onTapGesture(count: 2) {
            dismiss()
        }
    }
}
#endif
