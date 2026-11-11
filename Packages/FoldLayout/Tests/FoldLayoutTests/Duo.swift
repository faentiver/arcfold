import FoldLayout

/// The sizes the iOS 27.1 Simulator reports for iPhone Duo, at scale 3
/// (docs/wissen/falz.md), and geometries built from them. The inner display
/// is an assumption until the device test: safe area 0, the fold in the middle.
enum Duo {
    static let scale = 3

    /// The outer display, 466 × 678 pt.
    static let outer = PixelSize(width: 1398, height: 2034)
    /// Turned sideways; not measurable in the Simulator.
    static let outerLandscape = PixelSize(width: 2034, height: 1398)
    /// The inner display held upright (the fold across), 669 × 951 pt.
    static let inner = PixelSize(width: 2007, height: 2853)
    /// The inner display held like a book (the fold from top to bottom), 951 × 669 pt.
    static let innerLandscape = PixelSize(width: 2853, height: 2007)

    /// The vertical bar at the trailing edge, 84 pt, and the home indicator,
    /// 34 pt: 382 × 644 pt are left (measured).
    static let outerBar = PixelInsets(bottom: 34 * 3, right: 84 * 3)
    /// With `.toolbarVerticalBehavior(.disabled)` the bar moves to the top,
    /// 82 pt: 466 × 562 pt are left (measured).
    static let outerBarOnTop = PixelInsets(top: 82 * 3, bottom: 34 * 3)

    /// The closed device, upright, with the bar at the side or on top.
    static func closed(barOnTop: Bool) -> FoldGeometry {
        FoldGeometry(container: outer, safeArea: barOnTop ? outerBarOnTop : outerBar, scale: scale)
    }

    /// The closed device turned sideways as the real pose reports it: the bar
    /// on top, 82 pt, or at the leading edge, 84 pt, and the home indicator,
    /// 34 pt (measured with the screenshot tour).
    static func closedSideways(barOnTop: Bool) -> FoldGeometry {
        FoldGeometry(container: outerLandscape,
                     safeArea: barOnTop ? outerBarOnTop : PixelInsets(left: 84 * 3, bottom: 34 * 3), scale: scale)
    }

    /// The inner display as the real poses report it: the home indicator,
    /// 34 pt, and a division region of 121 px in the middle with margins of
    /// 20 pt (measured with the screenshot tour). Sideways the fold runs from
    /// top to bottom (open and the book), upright across (flat and tabletop).
    static func measuredInner(sideways: Bool, active: Bool) -> FoldGeometry {
        let safeArea = PixelInsets(bottom: 34 * 3)
        if sideways {
            return FoldGeometry(container: innerLandscape, safeArea: safeArea,
                                fold: PixelRect(x: 1366, y: 0, width: 121, height: innerLandscape.height),
                                foldMargins: PixelInsets(left: 60, right: 60), isFoldActive: active, scale: scale)
        }
        return FoldGeometry(container: inner, safeArea: safeArea,
                            fold: PixelRect(x: 0, y: 1366, width: inner.width, height: 121),
                            foldMargins: PixelInsets(top: 60, bottom: 60), isFoldActive: active, scale: scale)
    }

    /// A fold across the inner display, `band` points high, with `margin`
    /// points of margins above and below it inside the region.
    static func foldAcross(_ container: PixelSize = inner, band: Int, margin: Int = 0, active: Bool) -> FoldGeometry {
        let height = (band + 2 * margin) * scale
        let fold = PixelRect(x: 0, y: (container.height - height) / 2, width: container.width, height: height)
        return FoldGeometry(container: container, fold: fold,
                            foldMargins: PixelInsets(top: margin * scale, bottom: margin * scale),
                            isFoldActive: active, scale: scale)
    }

    /// A fold from top to bottom of the inner display, `band` points wide.
    static func foldDown(_ container: PixelSize = innerLandscape, band: Int, margin: Int = 0, active: Bool) -> FoldGeometry {
        let width = (band + 2 * margin) * scale
        let fold = PixelRect(x: (container.width - width) / 2, y: 0, width: width, height: container.height)
        return FoldGeometry(container: container, fold: fold,
                            foldMargins: PixelInsets(left: margin * scale, right: margin * scale),
                            isFoldActive: active, scale: scale)
    }
}
