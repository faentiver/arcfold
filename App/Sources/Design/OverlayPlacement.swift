import CoreGraphics
import FoldLayout

/// Where the overlays of a game sit, in points of the whole game view, the
/// coordinates of `GameStage`: the pause button, the debug overlay, notices,
/// the status chip and the message of a failed start (ADR 0007). A pure function of `GameLayout` (ADR 0006)
/// and the touch controls built from it, so tests check it against every
/// system and pose: no overlay of glass covers a touch button with its slop,
/// the reach of the pad, the pause button, the DS touch screen or the fold.
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
    /// The area the debug overlay is laid out in, from its top leading
    /// corner: inside the safe area and free of everything that takes
    /// touches and of the fold, so that its card covers no button, no pad
    /// and no touch screen in any pose. The card wraps its lines to the
    /// width and takes a smaller type where the height is short.
    var debugArea: CGRect
    /// The screen that notices and the chip stay on: the upper or only
    /// screen, never the touch screen.
    var pictureArea: CGRect
    /// The column the status chip and a notice are stacked in, the chip
    /// above the notice, aligned to its bottom edge: free of everything that
    /// takes touches and of the fold over its whole height, so that a notice
    /// of any length grows upwards in it and moves the chip along.
    var noticeColumn: CGRect
    /// Where the message of a game that could not start and its button are
    /// centred: the safe area of one screen, never across the fold.
    var failureArea: CGRect
    /// Distance of the overlays from the edges.
    var inset: CGFloat

    /// The height a notice of three lines needs at the default size.
    static let toastHeight: CGFloat = 72
    /// The height a status chip of two lines needs at the default size.
    static let chipHeight: CGFloat = 40
    /// The widest the status chip may become.
    static let chipMaxWidth: CGFloat = 320
    /// The measurements of the debug overlay at its largest type: about
    /// 900 characters with the room that wrapping at words wastes, in a
    /// monospaced type of 10 pt (6.02 × 12 pt a character) with 2 pt between
    /// the lines and 6 pt around them. An area that holds as many is large
    /// enough; among those the one nearest the top leading corner wins.
    static let debugCharacters: CGFloat = 900
    static let debugCharacterSize = CGSize(width: 6.02, height: 14)
    static let debugPadding: CGFloat = 6
    /// The narrowest column for a notice: sideways the upper DS screen is
    /// 256 pt wide, and the shoulder buttons or the reach of the pad take a
    /// few points off its sides.
    static let toastMinWidth: CGFloat = 200
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

        failureArea = Self.failureArea(in: geometry)

        // Notices and the chip stay on the picture, clear of everything
        // that takes touches and of the fold, where glass must not lie.
        let obstacles = Self.obstacles(layout: layout, geometry: geometry, controls: controls, pauseTarget: pauseTarget)
        let pictureIndex = layout.screens.indices.first { $0 != layout.touchScreenIndex } ?? 0
        let picture = layout.screens.isEmpty ? safe : points(layout.screens[pictureIndex].destination)
        pictureArea = picture
        noticeColumn = Self.noticeColumn(in: picture, inset: inset, obstacles: obstacles)
        debugArea = Self.debugArea(in: safe, inset: inset, obstacles: obstacles)
    }

    /// The area of the debug overlay in the safe area `safe`: the free
    /// rectangle that holds the most of its text, and among those that hold
    /// all of it the one nearest the top, then the leading edge, then the
    /// widest, where the fewest lines wrap.
    static func debugArea(in safe: CGRect, inset: CGFloat, obstacles: [CGRect]) -> CGRect {
        let area = safe.insetBy(dx: inset, dy: inset)
        func score(_ rect: CGRect) -> [CGFloat] {
            [min(debugCapacity(of: rect.size), debugCharacters), -rect.minY, -rect.minX, rect.width]
        }
        let free = freeRects(in: area, obstacles: obstacles, gap: spacing)
        return free.max { score($0).lexicographicallyPrecedes(score($1)) }
            ?? CGRect(x: area.minX, y: area.minY, width: 0, height: 0)
    }

    /// How many characters of the debug overlay's largest type fit `size`.
    static func debugCapacity(of size: CGSize) -> CGFloat {
        let columns = ((size.width - 2 * debugPadding) / debugCharacterSize.width).rounded(.down)
        let rows = ((size.height - 2 * debugPadding) / debugCharacterSize.height).rounded(.down)
        return max(0, columns) * max(0, rows)
    }

    /// The column of the status chip and the notices in `picture`: as wide
    /// as a notice may become, on the free rectangle that holds the chip and
    /// a notice of three lines and reaches lowest, the largest of those;
    /// where none is that high, on the highest one. A rectangle too narrow
    /// for a notice only wins when there is no wider one.
    static func noticeColumn(in picture: CGRect, inset: CGFloat, obstacles: [CGRect]) -> CGRect {
        let area = CGRect(x: picture.minX + inset, y: picture.minY + inset, width: max(0, picture.width - 2 * inset),
                          height: max(0, picture.height - inset - toastBottomMargin))
        let width = min(Metrics.toastMaxWidth(for: picture.width), area.width)
        let minimumWidth = min(toastMinWidth, width)
        let full = heightForNoticeAndChip
        func score(_ rect: CGRect) -> [CGFloat] {
            let height = min(rect.height, full)
            let centred = -abs(rect.midX - area.midX)
            return rect.width >= minimumWidth - 0.001
                ? [1, height, rect.maxY, min(rect.width, width) * rect.height, centred]
                : [0, rect.width, height, rect.maxY, centred]
        }
        let free = freeRects(in: area, obstacles: obstacles, gap: spacing)
        guard let best = free.max(by: { score($0).lexicographicallyPrecedes(score($1)) }) else {
            return CGRect(x: area.midX, y: area.maxY, width: 0, height: 0)
        }
        let columnWidth = min(width, best.width)
        return CGRect(x: best.midX - columnWidth / 2, y: best.minY, width: columnWidth, height: best.height)
    }

    /// The height of the status chip above a notice of three lines at the
    /// default size.
    static let heightForNoticeAndChip = chipHeight + spacing + toastHeight

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

    /// The largest rectangles inside `area` that keep `gap` from every
    /// obstacle: for every stretch across between two edges, every run down
    /// that nothing blocks. Each free rectangle of `area` lies inside one of
    /// them.
    static func freeRects(in area: CGRect, obstacles: [CGRect], gap: CGFloat) -> [CGRect] {
        guard area.width > 0, area.height > 0 else { return [] }
        let blockers = obstacles.map { $0.insetBy(dx: -gap, dy: -gap) }
            .filter { $0.minX < area.maxX && $0.maxX > area.minX && $0.minY < area.maxY && $0.maxY > area.minY }
        let lefts = [area.minX] + blockers.map(\.maxX).filter { $0 > area.minX && $0 < area.maxX }
        let rights = [area.maxX] + blockers.map(\.minX).filter { $0 > area.minX && $0 < area.maxX }
        var rects: [CGRect] = []
        for left in lefts {
            for right in rights where right > left {
                let inTheWay = blockers.filter { $0.minX < right && $0.maxX > left }.sorted { $0.minY < $1.minY }
                var top = area.minY
                for blocker in inTheWay {
                    if blocker.minY > top {
                        rects.append(CGRect(x: left, y: top, width: right - left, height: min(blocker.minY, area.maxY) - top))
                    }
                    top = max(top, blocker.maxY)
                }
                if area.maxY > top {
                    rects.append(CGRect(x: left, y: top, width: right - left, height: area.maxY - top))
                }
            }
        }
        return rects
    }
}
