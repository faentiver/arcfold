import FoldLayout
import SwiftUI

/// A fold that divides a view from top to bottom: the Duo held like a book,
/// where the division region is active and higher than wide. The system
/// divides its own apps there, Settings at the middle of the fold, and
/// nothing of the library lies on the region either. A fold across the view
/// (tabletop) and an inactive fold (open flat) divide nothing, as in the
/// system.
nonisolated enum FoldDivision {
    /// The distance a list or a text on one page keeps from the fold: the
    /// system's margin of the Duo, which the page has at its other edge.
    static let pageMargin = SystemMargins.standard.leading

    /// The division region with its margins, in points from the leading
    /// edge of the safe area of `geometry`; nil when no fold divides it.
    static func range(in geometry: FoldGeometry, isRightToLeft: Bool = false) -> ClosedRange<CGFloat>? {
        let safe = geometry.safeBounds
        guard geometry.isFoldActive, let fold = geometry.fold, fold.height > fold.width,
              fold.minX > safe.minX, fold.maxX < safe.maxX else { return nil }
        let scale = CGFloat(max(1, geometry.scale))
        // The geometry counts from the left.
        let left = CGFloat(fold.minX - safe.minX) / scale
        let right = CGFloat(fold.maxX - safe.minX) / scale
        let width = CGFloat(safe.width) / scale
        return isRightToLeft ? (width - right)...(width - left) : left...right
    }

    /// What the first page leaves free at the trailing edge of the safe
    /// area: the fold and the second page. 0 without a dividing fold.
    static func trailingInsetOfFirstPage(in geometry: FoldGeometry, isRightToLeft: Bool = false) -> CGFloat {
        guard let range = range(in: geometry, isRightToLeft: isRightToLeft) else { return 0 }
        return CGFloat(geometry.safeBounds.width) / CGFloat(max(1, geometry.scale)) - range.lowerBound
    }
}

extension View {
    /// Keeps one column of content, such as a list, a text or an empty
    /// state, on the first page while a fold divides the window from top to
    /// bottom: the content ends a margin before the division region, its
    /// background still fills the window. Without such a fold it changes nothing. For a view
    /// that fills the safe area.
    func onFirstFoldPage() -> some View {
        modifier(FirstFoldPage())
    }

    /// Reports whether a fold divides this view from top to bottom, when it
    /// appears and whenever that changes. For a view that fills the safe area.
    func onFoldDivisionChange(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(FoldDivisionReader(action: action))
    }
}

private struct FirstFoldPage: ViewModifier {
    @State private var geometry: FoldGeometry?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.trailing, inset)
            // Behind the content, so that the padding does not reach the
            // measurement.
            .background {
                Color.clear
                    .onFoldGeometryChange(scale: max(1, Int(displayScale.rounded()))) { geometry = $0 }
            }
    }

    private var inset: CGFloat {
        guard var geometry else { return 0 }
        #if DEBUG
        // The artificial fold of debug builds, as in a game.
        geometry = DebugRemote.shared.foldOverride?.applied(to: geometry) ?? geometry
        #endif
        let inset = FoldDivision.trailingInsetOfFirstPage(in: geometry, isRightToLeft: layoutDirection == .rightToLeft)
        // The content keeps the distance from the fold that it keeps from
        // the leading edge, as the sidebar of Settings does. As safe area,
        // because content margins of a list replace its safe area.
        return inset > 0 ? inset + FoldDivision.pageMargin : 0
    }
}

private struct FoldDivisionReader: ViewModifier {
    let action: (Bool) -> Void
    @State private var isDivided: Bool?
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .onFoldGeometryChange(scale: max(1, Int(displayScale.rounded()))) { geometry in
                        let divided = FoldDivision.range(in: geometry) != nil
                        guard divided != isDivided else { return }
                        isDivided = divided
                        action(divided)
                    }
            }
    }
}
