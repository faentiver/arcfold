import SwiftUI

/// Shown instead of the game when it could not start: the system's empty
/// state over the game's artwork, and a prominent glass button to leave.
struct GameFailureView: View {
    let message: String
    let close: () -> Void

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GameArtwork(variant: .backdrop)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    GameFailureView(message: "Core Failed to Load: dlopen failed") {}
        .environment(\.gameStyle, GameStyle(id: "1", name: "Selftest"))
        .preferredColorScheme(.dark)
}
