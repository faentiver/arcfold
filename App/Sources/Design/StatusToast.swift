import Accessibility
import SwiftUI

/// A short notice over the game picture, in in-game glass. It never takes a
/// touch (rule R6), so it cannot block a button below it, and VoiceOver
/// announces it.
struct StatusToast: View {
    let text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GlassEffectContainer {
            Label {
                Text(text)
            } icon: {
                Image(systemName: "info.circle.fill")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            // Three lines at the usual sizes; from the accessibility sizes on
            // the whole text, or large text would cut the message off.
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            .multilineTextAlignment(.leading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .gameGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), isSmallLabel: true)
            .glassEffectTransition(.materialize)
        }
        // Its own height, even where the anchor of OverlayPlacement is lower:
        // the anchor aligns the bottom edge, so a taller notice grows upwards.
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
        .task(id: text) {
            AccessibilityNotification.Announcement(text).post()
        }
    }

    /// How a notice comes and goes: rising 8 pt, or a fade only with Reduce
    /// Motion.
    static func transition(prefersFades: Bool) -> AnyTransition {
        prefersFades ? .opacity : .opacity.combined(with: .offset(y: 8))
    }
}

/// A notice that stays, such as a missing audio output.
struct StatusChip: View {
    let text: String

    var body: some View {
        GlassEffectContainer {
            Label {
                Text(text)
            } icon: {
                Image(systemName: "speaker.slash.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.caption2)
            .foregroundStyle(.white)
            // Like a notice, it stops growing at accessibility2, so it stays
            // inside the picture area upright.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // A capsule as long as it is one line at the usual sizes; with
            // large text it wraps, and a capsule's round ends cut the text.
            .gameGlass(in: RoundedRectangle(cornerRadius: 12.5, style: .continuous), isSmallLabel: true)
        }
        // Like the notice: its own height, growing away from its anchor.
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
    }
}

#Preview {
    VStack(spacing: 16) {
        StatusToast(text: "The save could not be written: disk full")
        StatusChip(text: "No audio output")
    }
    .padding(40)
    .background(.white)
}
