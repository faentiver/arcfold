import Accessibility
import SwiftUI

/// The status chip above a notice, where `OverlayPlacement.noticeColumn`
/// puts them: one stack in one glass container (rule R4), aligned to the
/// bottom of the column. A notice shows its whole text at every size and
/// grows upwards; the chip moves up with it, so the two never overlap. They
/// never take a touch (rule R6).
struct NoticeStack: View {
    /// A problem that stays, such as a missing audio output.
    let audioProblem: String?
    let notice: String?

    @Environment(\.prefersFades) private var prefersFades

    var body: some View {
        // Spacing 0: the chip and the notice stay two shapes.
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: OverlayPlacement.spacing) {
                if let audioProblem {
                    StatusChip(text: audioProblem)
                        .frame(maxWidth: OverlayPlacement.chipMaxWidth)
                        // In a column too low for both, the notice gives way.
                        .layoutPriority(1)
                }
                if let notice {
                    StatusToast(text: notice)
                        .transition(StatusToast.transition(prefersFades: prefersFades))
                }
            }
        }
        .animation(Motion.appear(reduceMotion: prefersFades), value: notice)
        .allowsHitTesting(false)
    }
}

/// A short notice over the game picture, in in-game glass. VoiceOver
/// announces it.
struct StatusToast: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "info.circle.fill")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        // No line limit: the column of OverlayPlacement bounds the height,
        // and a limit cut real messages off where the picture is narrow, as
        // on the upper DS screen sideways (256 pt).
        .multilineTextAlignment(.leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .gameGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), isSmallLabel: true)
        .glassEffectTransition(.materialize)
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
}

#Preview {
    NoticeStack(audioProblem: "No audio output", notice: "The save could not be written: disk full")
        .padding(40)
    .background(.white)
}
