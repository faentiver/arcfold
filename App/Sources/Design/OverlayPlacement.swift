import CoreGraphics
import FoldLayout

/// Where the overlays of a game sit, in points of the whole game view, the
/// coordinates of `GameStage`: the pause button, the debug overlay, notices,
/// the status chip and the message of a failed start (ADR 0007). A pure function of `GameLayout` (ADR 0006)
/// and the touch controls built from it, so tests check it against every
/// system and pose: no overlay covers a touch button with its slop, the reach
/// of the pad, the pause button, the DS touch screen or the fold.
///
/// Keeps the two faults of M1 fixed: sideways the pause button covered R,
/// upright a notice lay over Select and Start and took their touches.
nonisolated struct OverlayPlacement: Sendable, Hashable {
    /// The pause button as drawn: its place between Select and Start with
    /// touch controls, the corner `GameLayout.pauseButton` names without
    /// them; nil when there is neither.
    var pauseButton: CGRect?
    /// Where the pause button takes touches: at least 44 × 44 pt around it.
    var pauseTarget: CGRect?
    /// The top leading corner of the debug overlay, inside the safe area.
    var debugOrigin: CGPoint
    /// The widest the debug overlay may become, so that its lines wrap
    /// before a pause button in the upper half beside it.
    var debugMaxWidth: CGFloat
    /// The screen that notices and the chip stay on: the upper or only
    /// screen, never the touch screen.
    var pictureArea: CGRect
    /// The area a notice is laid out in, aligned to its bottom edge.
    var toastAnchor: CGRect
    /// The area the status chip is laid out in, aligned to its bottom edge:
    /// just above the notices.
    var chipAnchor: CGRect
    /// Where the message of a game that could not start and its button are
    /// centred: the safe area of one screen, never across the fold.
    var failureArea: CGRect
    /// Distance of the overlays from the edges.
    var inset: CGFloat

    /// The height a notice of up to three lines needs at the default size.
    static let toastHeight: CGFloat = 72
    /// The height a status chip of up to two lines needs at the default size.
    static let chipHeight: CGFloat = 40
    /// The widest the status chip may become.
    static let chipMaxWidth: CGFloat = 320
    /// How far down the debug overlay reaches at most from its corner, for
    /// the touch screen it must stay beside.
    static let debugReach: CGFloat = 200
    /// The narrowest the debug overlay becomes beside a touch screen.
    static let debugMinWidth: CGFloat = 200
    /// The narrowest a notice may become before it moves up instead.
    static let toastMinWidth: CGFloat = 240
    /// Space between the bottom of the picture and a notice, and between
    /// overlays.
    static let toastBottomMargin: CGFloat = 12
    static let spacing: CGFloat = 6

    /// `controls` are the touch controls `GameStage` draws for `layout`, nil
    /// while none show.
    init(layout: GameLayout, geometry: FoldGeometry, controls: TouchLayout?) {
        let scale = geometry.scale
        func points(_ rect: PixelRect) -> CGRect { rect.points(scale: scale) }
        let safe = points(geometry.safeBounds)
        let inset = Metrics.overlayInset(for: safe.width)
        self.inset = inset

        // The pause button: where GameLayout and TouchLayout put it.
        let pause = controls.map(\.pauseButton) ?? layout.pauseButton.map(points)
        pauseButton = pause
        pauseTarget = pause.map(Self.target(around:))

        // The debug overlay at the top leading corner of the safe area. Its
        // lines wrap before a pause button in the upper half beside it, and
        // before a touch screen that begins beside it, as in the book pose,
        // so that its card never darkens the touch screen.
        let origin = CGPoint(x: safe.minX + inset, y: safe.minY + inset)
        debugOrigin = origin
        var debugRight = safe.maxX - inset
        if let target = pauseTarget, target.minY < points(geometry.bounds).midY, target.minX > origin.x {
            debugRight = min(debugRight, target.minX - inset)
        }
        if let touch = layout.touchScreen.map({ points($0.destination) }),
           touch.minY < origin.y + Self.debugReach, touch.minX > origin.x + Self.debugMinWidth {
            debugRight = min(debugRight, touch.minX - inset)
        }
        debugMaxWidth = max(0, debugRight - origin.x)

        failureArea = Self.failureArea(in: geometry)

        // Notices and the chip stay on the picture, clear of everything
        // that takes touches and of the fold, where glass must not lie.
        let obstacles = Self.obstacles(layout: layout, geometry: geometry, controls: controls, pauseTarget: pauseTarget)
        let pictureIndex = layout.screens.indices.first { $0 != layout.touchScreenIndex } ?? 0
        let picture = layout.screens.isEmpty ? safe : points(layout.screens[pictureIndex].destination)
        pictureArea = picture
        let toastWidth = max(0, min(Metrics.toastMaxWidth(for: picture.width), picture.width - 2 * inset))
        let toast = Self.freeBand(in: picture, inset: inset, height: Self.toastHeight,
                                  bottom: picture.maxY - Self.toastBottomMargin, width: toastWidth,
                                  minimumWidth: min(Self.toastMinWidth, toastWidth), obstacles: obstacles)
        let chipWidth = min(toast.width, Self.chipMaxWidth)
        let chipBottom = toast.minY - Self.spacing
        if chipBottom - Self.chipHeight >= picture.minY + inset - 0.001 {
            toastAnchor = toast
            chipAnchor = Self.freeBand(in: picture, inset: inset, height: Self.chipHeight, bottom: chipBottom,
                                       width: chipWidth, minimumWidth: chipWidth, obstacles: obstacles + [toast],
                                       around: toast.midX)
        } else {
            // A picture too low for both, such as the DS sideways on an
            // iPhone (128 pt): the chip at its top, the notice below it, as
            // high as the rest; the notice grows upwards from its bottom.
            let chip = Self.freeBand(in: picture, inset: inset, height: Self.chipHeight,
                                     bottom: picture.minY + inset + Self.chipHeight, width: chipWidth,
                                     minimumWidth: chipWidth, obstacles: obstacles, around: toast.midX)
            chipAnchor = chip
            let top = min(chip.maxY + Self.spacing, toast.maxY)
            toastAnchor = CGRect(x: toast.minX, y: top, width: toast.width, height: toast.maxY - top)
        }
    }

    /// Where the message of a failed start is centred: the safe area, and
    /// with a fold the part of it above the fold, or left of a fold from top
    /// to bottom. That holds for an inactive fold and for one without a
    /// width too: the hinge lies there in every pose of the inner display,
    /// and text and a button across it read badly. An occlusion such as the
    /// camera takes the smaller part beside it away.
    static func failureArea(in geometry: FoldGeometry) -> CGRect {
        let scale = geometry.scale
        var area = geometry.safeBounds.points(scale: scale)
        if let fold = geometry.fold.map({ $0.points(scale: scale) }) {
            if fold.width > fold.height {
                area.size.height = max(0, min(area.maxY, fold.minY) - area.minY)
            } else {
                area.size.width = max(0, min(area.maxX, fold.minX) - area.minX)
            }
        }
        for occlusion in geometry.occlusions.map({ $0.points(scale: scale) }) where occlusion.intersects(area) {
            let parts = [
                CGRect(x: area.minX, y: area.minY, width: occlusion.minX - area.minX, height: area.height),
                CGRect(x: occlusion.maxX, y: area.minY, width: area.maxX - occlusion.maxX, height: area.height),
                CGRect(x: area.minX, y: area.minY, width: area.width, height: occlusion.minY - area.minY),
                CGRect(x: area.minX, y: occlusion.maxY, width: area.width, height: area.maxY - occlusion.maxY),
            ].filter { $0.width > 0 && $0.height > 0 }
            area = parts.max { $0.width * $0.height < $1.width * $1.height } ?? area
        }
        return area
    }

    /// The lowest picture that holds the notice and the chip one above the
    /// other.
    static func heightForNoticeAndChip(inset: CGFloat) -> CGFloat {
        2 * inset + chipHeight + spacing + toastHeight + toastBottomMargin - inset
    }

    /// The square that takes touches for a pause button drawn in `frame`.
    static func target(around frame: CGRect) -> CGRect {
        let side = PauseButton.minimumTarget
        return frame.insetBy(dx: min(0, (frame.width - side) / 2), dy: min(0, (frame.height - side) / 2))
    }

    /// Everything an overlay of glass must not cover, in points: every button
    /// with its slop, the reach of the pad, the pause button, the touch
    /// screen and the fold, active or not.
    static func obstacles(layout: GameLayout, geometry: FoldGeometry, controls: TouchLayout?,
                          pauseTarget: CGRect?) -> [CGRect] {
        var obstacles: [CGRect] = []
        if let controls {
            for button in controls.buttons {
                let slop = min(button.frame.width, button.frame.height) * TouchLayout.buttonSlop
                obstacles.append(button.frame.insetBy(dx: -slop, dy: -slop))
            }
            let reach = controls.pad.radius * TouchLayout.padReach
            obstacles.append(CGRect(x: controls.pad.center.x - reach, y: controls.pad.center.y - reach,
                                    width: 2 * reach, height: 2 * reach))
        }
        if let pauseTarget {
            obstacles.append(pauseTarget)
        }
        if let touchScreen = layout.touchScreen {
            obstacles.append(touchScreen.destination.points(scale: geometry.scale))
        }
        if let fold = geometry.fold, !fold.isEmpty {
            obstacles.append(fold.points(scale: geometry.scale))
        }
        return obstacles
    }

    /// A band of `height` inside `area` whose bottom is at most `bottom`,
    /// as wide as `width` and centred under `around` (the middle of the
    /// free stretch by default), on the widest stretch of the band that no
    /// obstacle covers. When that stretch is narrower than `minimumWidth`,
    /// the band moves up above the obstacles in its way; when it reaches
    /// the top of `area`, the widest stretch there wins.
    static func freeBand(in area: CGRect, inset: CGFloat, height: CGFloat, bottom: CGFloat, width: CGFloat,
                         minimumWidth: CGFloat, obstacles: [CGRect], around: CGFloat? = nil) -> CGRect {
        let left = area.minX + inset
        let right = area.maxX - inset
        let top = area.minY + inset
        var bottom = min(bottom, area.maxY - inset)
        var best: CGRect?
        while bottom - height >= top - 0.001 {
            let band = CGRect(x: left, y: bottom - height, width: max(0, right - left), height: height)
            let blockers = obstacles.filter { $0.intersects(band) }
            let stretch = widestFreeStretch(of: band, without: blockers)
            if best.map({ stretch.width > $0.width }) ?? true {
                best = stretch
            }
            if stretch.width >= minimumWidth {
                return centred(width: width, in: stretch, around: around)
            }
            // Above the highest obstacle in the way.
            guard let next = blockers.map(\.minY).min(), next - Self.spacing < bottom else { break }
            bottom = next - Self.spacing
        }
        return centred(width: width, in: best ?? CGRect(x: left, y: top, width: 0, height: height), around: around)
    }

    /// The widest stretch of `band` across which none of `blockers` lies.
    static func widestFreeStretch(of band: CGRect, without blockers: [CGRect]) -> CGRect {
        let covered = blockers.map { ($0.minX, $0.maxX) }.sorted { $0.0 < $1.0 }
        var start = band.minX
        var widest = CGRect(x: band.minX, y: band.minY, width: 0, height: band.height)
        for (minX, maxX) in covered {
            let end = min(minX, band.maxX)
            if end - start > widest.width {
                widest = CGRect(x: start, y: band.minY, width: end - start, height: band.height)
            }
            start = max(start, maxX)
        }
        if band.maxX - start > widest.width {
            widest = CGRect(x: start, y: band.minY, width: band.maxX - start, height: band.height)
        }
        return widest
    }

    /// A rectangle of `width`, at most the stretch's, centred under `around`
    /// as far as the stretch allows.
    static func centred(width: CGFloat, in stretch: CGRect, around: CGFloat?) -> CGRect {
        let width = max(0, min(width, stretch.width))
        let middle = around ?? stretch.midX
        let x = min(max(middle - width / 2, stretch.minX), stretch.maxX - width)
        return CGRect(x: x, y: stretch.minY, width: width, height: stretch.height)
    }
}
