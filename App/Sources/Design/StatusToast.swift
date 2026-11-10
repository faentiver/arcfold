import Accessibility
import SwiftUI

/// The status chip above a notice, where `OverlayPlacement.noticeColumn`
/// puts them: one stack in one glass container (rule R4), aligned to the
/// bottom of the column. A notice shows its whole text and grows upwards;
/// the chip moves up with it, so the two never overlap. They never take a
/// touch (rule R6), and VoiceOver announces a notice.
struct NoticeStack: View {
    /// A problem that stays, such as a missing audio output.
    let audioProblem: String?
    let notice: String?

    @Environment(\.prefersFades) private var prefersFades

    /// The largest text sizes the stack is tried with, in this order: it
    /// takes the first at which the chip and the whole notice fit the
    /// column. Up to the default size nothing changes; with larger text a
    /// low picture, such as the upper DS screen sideways, gets a smaller
    /// size rather than a notice cut off after its first words.
    nonisolated static let sizeLimits: [DynamicTypeSize] = [.accessibility2, .accessibility1, .xxxLarge, .xLarge, .large]

    var body: some View {
        ViewThatFits(in: .vertical) {
            // Each of these shows only when it fits, at its own height.
            stack(upTo: Self.sizeLimits[0]).fixedSize(horizontal: false, vertical: true)
            stack(upTo: Self.sizeLimits[1]).fixedSize(horizontal: false, vertical: true)
            stack(upTo: Self.sizeLimits[2]).fixedSize(horizontal: false, vertical: true)
            stack(upTo: Self.sizeLimits[3]).fixedSize(horizontal: false, vertical: true)
            // Too high even at the default size: the notice gives way.
            stack(upTo: Self.sizeLimits[4])
        }
        .animation(Motion.appear(reduceMotion: prefersFades), value: notice)
        .allowsHitTesting(false)
        .task(id: notice) {
            if let notice {
                AccessibilityNotification.Announcement(notice).post()
            }
        }
    }

    private func stack(upTo limit: DynamicTypeSize) -> some View {
        // Spacing 0: the chip and the notice stay two shapes.
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: OverlayPlacement.spacing) {
                if let audioProblem {
                    StatusChip(text: audioProblem)
                        .frame(maxWidth: OverlayPlacement.chipMaxWidth)
                        .layoutPriority(1)
                }
                if let notice {
                    StatusToast(text: notice)
                        .transition(StatusToast.transition(prefersFades: prefersFades))
                }
            }
        }
        .dynamicTypeSize(...limit)
    }
}

/// A short notice over the game picture, in in-game glass.
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
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .gameGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), isSmallLabel: true)
        .glassEffectTransition(.materialize)
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
