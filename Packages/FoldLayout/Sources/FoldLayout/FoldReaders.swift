#if os(iOS)
import SwiftUI

/// The hinge of a foldable iPhone as far as the game cares
/// (`DeviceHinge.Status` of iOS 27.1, without the angle).
public enum HingeState: Sendable, Hashable {
    case closed
    case partiallyOpen
    case fullyOpen
}

extension View {
    /// Reports what `GameLayout` needs about this view, in pixels at `scale`:
    /// its size, its safe area, the division region (the fold) from
    /// `GeometryProxy.reservedRegions(kind: .division, options:
    /// .includeInactive, layoutDirectionBehavior: .fixed)` and the active
    /// occlusion regions (`kind: .occlusion`, such as the camera), moved into
    /// the coordinates of the whole view. Called when the view appears and
    /// whenever any of it changes, also when only a reserved region moves.
    /// Before iOS 27.1 the fold is always nil and there are no occlusions
    /// (ADR 0006).
    ///
    /// Attach it to a view that fills the safe area, not to one that ignores
    /// it: such a view reports no safe area insets.
    public func onFoldGeometryChange(scale: Int, perform action: @escaping (FoldGeometry) -> Void) -> some View {
        modifier(FoldGeometryReader(scale: scale, action: action))
    }

    /// Reports the hinge with `onHingeChange` (iOS 27.1): the state before and
    /// after each change, starting with nil and the current state when the
    /// view appears. Both are nil on devices without a hinge and before iOS
    /// 27.1. The game pauses when the state becomes `.closed` (ADR 0006).
    public func onHingeStateChange(perform action: @escaping (_ old: HingeState?, _ new: HingeState?) -> Void) -> some View {
        modifier(HingeStateReader(action: action))
    }
}

/// Measures the geometry; see `onFoldGeometryChange(scale:perform:)`.
struct FoldGeometryReader: ViewModifier {
    let scale: Int
    let action: (FoldGeometry) -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        let scale = max(1, scale)
        let isRightToLeft = layoutDirection == .rightToLeft
        // The transform runs outside the main actor; it reads the proxy only.
        // It also runs when nothing but a reserved region changed (ADR 0006).
        content.onGeometryChange(for: FoldGeometry.self) { proxy in
            FoldGeometry(measuring: proxy, scale: scale, isRightToLeft: isRightToLeft)
        } action: { geometry in
            action(geometry)
        }
    }
}

extension FoldGeometry {
    /// The geometry of the whole view around `proxy`, which belongs to a view
    /// that fills the safe area: its size plus the insets is the whole view,
    /// and the reserved regions are local to it, so they move by the insets
    /// at the top and on the left. Insets and the fold are rounded outwards,
    /// to whole pixels.
    nonisolated init(measuring proxy: GeometryProxy, scale: Int, isRightToLeft: Bool) {
        let insets = proxy.safeAreaInsets
        // EdgeInsets follow the layout direction; the regions are read with
        // the fixed (left-to-right) behaviour.
        let left = isRightToLeft ? insets.trailing : insets.leading
        let right = isRightToLeft ? insets.leading : insets.trailing
        let s = CGFloat(scale)
        let container = PixelSize(
            width: Int(((proxy.size.width + left + right) * s).rounded()),
            height: Int(((proxy.size.height + insets.top + insets.bottom) * s).rounded())
        )
        var fold: PixelRect?
        var margins = PixelInsets.zero
        var isActive = false
        var occlusions: [PixelRect] = []
        let whole = PixelRect(x: 0, y: 0, width: container.width, height: container.height)
        if #available(iOS 27.1, *) {
            if let region = proxy.reservedRegions(kind: .division, options: .includeInactive,
                                                  layoutDirectionBehavior: .fixed).first {
                let frame = region.frame.offsetBy(dx: left, dy: insets.top)
                fold = PixelRect.covering(frame, scale: scale).intersection(whole)
                let m = region.margins
                margins = PixelInsets.covering(
                    top: m.top, left: isRightToLeft ? m.trailing : m.leading,
                    bottom: m.bottom, right: isRightToLeft ? m.leading : m.trailing, scale: scale
                )
                isActive = region.isActive
            }
            occlusions = proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)
                .filter(\.isActive)
                .map { PixelRect.covering($0.frame.offsetBy(dx: left, dy: insets.top), scale: scale).intersection(whole) }
                .filter { !$0.isEmpty }
        }
        self.init(
            container: container,
            safeArea: PixelInsets.covering(top: insets.top, left: left, bottom: insets.bottom, right: right, scale: scale),
            fold: fold, foldMargins: margins, isFoldActive: isActive, scale: scale, occlusions: occlusions
        )
    }
}

/// Follows the hinge; see `onHingeStateChange(perform:)`.
struct HingeStateReader: ViewModifier {
    let action: (_ old: HingeState?, _ new: HingeState?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { old, new in
                action(Self.state(of: old.hinge), Self.state(of: new.hinge))
            }
        } else {
            content
        }
    }

    /// `DeviceHinge.Status` is a struct with static members, not an enum; a
    /// status this version does not know counts as no information.
    @available(iOS 27.1, *)
    static func state(of hinge: DeviceHinge?) -> HingeState? {
        guard let hinge else { return nil }
        switch hinge.status {
        case .closed: return .closed
        case .partiallyOpen: return .partiallyOpen
        case .fullyOpen: return .fullyOpen
        default: return nil
        }
    }
}
#endif
