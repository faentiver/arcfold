import SwiftUI

/// A screen before the first frame: the game's artwork, blurred and dimmed,
/// with a spinner while the core loads; on the DS the spinner shows on the
/// upper screen only.
struct LoadingBackdrop: View {
    let isLoading: Bool
    var showsProgress = true

    var body: some View {
        if isLoading {
            GameArtwork(variant: .backdrop)
                .overlay {
                    if showsProgress {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
        } else {
            Color.black
        }
    }
}

#Preview {
    LoadingBackdrop(isLoading: true)
        .frame(width: 382, height: 255)
        .environment(\.gameStyle, GameStyle(id: "1", name: "Selftest"))
        .preferredColorScheme(.dark)
}
