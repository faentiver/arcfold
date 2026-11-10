import SwiftUI

/// Shown instead of the game when it could not start: the system's empty
/// state over the game's artwork, and a prominent glass button to leave.
/// The artwork fills the view; the message and the button stay on one
/// screen, in the area `OverlayPlacement` names, so that no glass and no
/// text lie across the fold (rule R6).
struct GameFailureView: View {
    let message: String
    /// Where the message is centred, in the coordinates of the view; nil
    /// centres it in the whole view.
    var area: CGRect?
    let close: () -> Void

    var body: some View {
        Group {
            if let area {
                // Scrolls only when large text no longer fits the screen.
                ScrollView {
                    content
                        .frame(minHeight: area.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: area.width, height: area.height)
                .offset(x: area.minX, y: area.minY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            GameArtwork(variant: .backdrop)
                .ignoresSafeArea()
        }
    }

    private var content: some View {
        ContentUnavailableView {
            Label {
                Text("The Game Could Not Start", comment: "Title when a game fails to start.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
        } description: {
            Text(message)
        } actions: {
            Button(action: close) {
                Text("Close", comment: "Button that leaves a game that could not start.")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}

#Preview {
    GameFailureView(message: "Core Failed to Load: dlopen failed") {}
        .environment(\.gameStyle, GameStyle(id: "1", name: "Selftest"))
        .preferredColorScheme(.dark)
}
