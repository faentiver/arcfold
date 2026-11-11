import FoldLayout
import SwiftUI

/// What the case of the console consists of in one layout, in points of the
/// game view: the bezels around the screens, the hinge and the ring around
/// the camera. A pure function of `GameLayout` and `FoldGeometry`, so tests
/// check it against every pose (ADR 0007).
nonisolated struct CaseLayout: Sendable, Hashable {
    /// The dark frame around a screen, set into the case.
    struct Bezel: Sendable, Hashable {
        var frame: CGRect
        /// The radius of its upper and of its lower corners: small where
        /// the bezel ends at a hinge.
        var topCorner: CGFloat
        var bottomCorner: CGFloat
        /// The bezel ends at the left or right edge of the view, square:
        /// where it does not fit beside a screen, it is a band across the
        /// view.
        var endsAtLeftEdge = false
        var endsAtRightEdge = false
    }

    struct Hinge: Sendable, Hashable {
        enum Kind: Sendable, Hashable {
            /// The fold of the device, across the whole view.
            case fold
            /// Between two stacked screens on a display without a fold: the
            /// console has a hinge of its own there, with L and R at its ends.
            case bar
        }

        var kind: Kind
        /// The whole hinge. Of a bar the barrel between L and R.
        var frame: CGRect
        /// The hinge runs from left to right.
        var isHorizontal: Bool
        /// The device is folded at the hinge: it is drawn with more depth.
        var isBent: Bool
    }

    var size: CGSize
    var screens: [CGRect]
    var bezels: [Bezel]
    var hinge: Hinge?
    /// The camera of the outer display, which the case frames with a ring.
    var lens: CGRect?
    /// The speaker the case shows opposite the camera, as its mirror image.
    var speaker: CGRect?

    /// What the barrel of a hinge keeps from L and R at its ends.
    static let hingeGap: CGFloat = 4
    /// The corners of a bezel where it ends at a hinge.
    static let cornerAtHinge: CGFloat = 3
    /// The largest reserved region that still counts as a camera.
    static let largestLens: CGFloat = 64

    init(layout: GameLayout, geometry: FoldGeometry) {
        let scale = geometry.scale
        size = geometry.container.points(scale: scale)
        let view = CGRect(origin: .zero, size: size)
        screens = layout.screens.map { $0.destination.points(scale: scale) }

        // The hinge: the row GameLayout keeps for a hinge of the console
        // where the layout has no fold, or else the fold of the device. A
        // fold at the edge of the view, which the layout leaves aside, is
        // no hinge of the console then.
        var hinge: Hinge?
        var row: CGRect?
        if layout.hinge == nil, let fold = geometry.fold?.points(scale: scale), fold.width > 0, fold.height > 0 {
            hinge = Hinge(kind: .fold, frame: fold, isHorizontal: fold.width >= fold.height, isBent: geometry.isFoldActive)
        } else if let hingeRow = layout.hinge?.points(scale: scale), hingeRow.height > 0 {
            row = hingeRow
            var barrel = hingeRow
            // L and R stand at its ends; the barrel lies between them and
            // is as high as they are drawn.
            if let zones = layout.controls {
                let left = (zones.leftShoulderCap ?? zones.leftShoulder).points(scale: scale)
                let right = (zones.rightShoulderCap ?? zones.rightShoulder).points(scale: scale)
                let inset = zones.leftShoulderCap == nil ? 0 : TouchLayout.slimWell
                if left.maxX < right.minX {
                    barrel = CGRect(x: left.maxX + Self.hingeGap, y: hingeRow.minY + inset,
                                    width: right.minX - left.maxX - 2 * Self.hingeGap, height: hingeRow.height - 2 * inset)
                }
            }
            hinge = Hinge(kind: .bar, frame: barrel, isHorizontal: true, isBent: true)
        }
        self.hinge = hinge

        // A bezel around every screen; screens that lie close together
        // share one, and so do two with a hinge of the console between
        // them, which then lies across their bezel. Beside a hinge a bezel
        // ends at its row with small corners; a single screen that spans
        // the fold keeps its whole bezel, which then lies over the hinge.
        // Where a control stands closer below a screen than the bezel is
        // wide, the bezel ends half way.
        let width = ConsoleSkin.bezelWidth
        var frames: [CGRect] = []
        var shortened: [CGFloat] = []
        for screen in screens {
            var frame = screen.insetBy(dx: -width, dy: -width)
            if let zones = layout.controls {
                for zone in [zones.pad, zones.face, zones.menu].map({ $0.points(scale: scale) })
                    where zone.minY >= screen.maxY && zone.minY < frame.maxY && zone.minX < frame.maxX && zone.maxX > frame.minX {
                    frame.size.height = (screen.maxY + zone.minY) / 2 - frame.minY
                    shortened.append(frame.maxY)
                }
            }
            if let index = frames.firstIndex(where: { $0.intersects(frame) }) {
                frames[index] = frames[index].union(frame)
            } else {
                frames.append(frame)
            }
        }
        if let row, frames.contains(where: { $0.midY < row.minY }), frames.contains(where: { $0.midY > row.maxY }) {
            frames = [frames.dropFirst().reduce(frames[0]) { $0.union($1) }]
        }
        bezels = frames.map { whole in
            var frame = whole
            var top = ConsoleSkin.bezelCorner
            var bottom = ConsoleSkin.bezelCorner
            let inner = frame.insetBy(dx: width, dy: width)
            let across = row ?? hinge.flatMap { $0.isHorizontal ? $0.frame : nil }
            if let across, !inner.intersects(across) {
                if inner.maxY <= across.minY, frame.maxY > across.minY {
                    frame.size.height = across.minY - frame.minY
                    bottom = Self.cornerAtHinge
                } else if inner.minY >= across.maxY, frame.minY < across.maxY {
                    frame = CGRect(x: frame.minX, y: across.maxY, width: frame.width, height: frame.maxY - across.maxY)
                    top = Self.cornerAtHinge
                }
            }
            if shortened.contains(frame.maxY) {
                bottom = Self.cornerAtHinge
            }
            // Where the bezel does not fit beside a screen, the screen runs
            // from edge to edge, and the bezel ends square at the edge of
            // the view instead of being cut off half way.
            let left = frame.minX < view.minX
            let right = frame.maxX > view.maxX
            if left || right {
                frame = CGRect(x: max(frame.minX, view.minX), y: frame.minY,
                               width: min(frame.maxX, view.maxX) - max(frame.minX, view.minX), height: frame.height)
            }
            return Bezel(frame: frame, topCorner: top, bottomCorner: bottom, endsAtLeftEdge: left, endsAtRightEdge: right)
        }

        // The camera: the small, nearly square reserved region. Its mirror
        // image at the other side is the speaker, where nothing else lies.
        let lens = geometry.occlusions.map { $0.points(scale: scale) }.first {
            max($0.width, $0.height) <= Self.largestLens && abs($0.width - $0.height) <= 2 && view.contains($0)
        }
        self.lens = lens
        let bezelFrames = bezels.map(\.frame)
        speaker = lens.flatMap { lens -> CGRect? in
            let mirror = CGRect(x: size.width - lens.maxX, y: lens.minY, width: lens.width, height: lens.height)
            let ring = mirror.insetBy(dx: -ConsoleSkin.lensRing, dy: -ConsoleSkin.lensRing)
            guard !mirror.intersects(lens.insetBy(dx: -2 * ConsoleSkin.lensRing, dy: 0)),
                  !bezelFrames.contains(where: ring.intersects) else { return nil }
            return mirror
        }
    }
}

/// The case of the console: it fills the whole game view around the
/// screens, up to every edge and below the status area of the system. A
/// fine gradient with light from above, the bezels set into it, the hinge at
/// the fold, a ring around the camera. It leaves the screens open, where
/// the picture shows from below. Drawn once per layout: nothing in it
/// changes while a game runs, so it costs nothing per frame (ADR 0007).
struct ConsoleCase: View, Equatable {
    let layout: CaseLayout
    let skin: ConsoleSkin

    nonisolated static func == (lhs: ConsoleCase, rhs: ConsoleCase) -> Bool {
        lhs.layout == rhs.layout && lhs.skin == rhs.skin
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            Self.draw(layout, skin: skin, in: &context, size: size)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static func draw(_ layout: CaseLayout, skin: ConsoleSkin, in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        drawBody(bounds, skin: skin, in: &context)
        // The fold lies below the bezels: a picture across it keeps its
        // whole bezel. The hinge of the console lies across theirs.
        if let hinge = layout.hinge, hinge.kind == .fold {
            drawFold(hinge, skin: skin, in: &context)
        }
        for bezel in layout.bezels {
            drawBezel(bezel, skin: skin, in: &context)
        }
        if let hinge = layout.hinge, hinge.kind == .bar {
            drawBar(hinge, skin: skin, in: &context)
        }
        // The camera and the speaker opposite it: two dishes of one size.
        // The camera is the system's; the dishes and the speaker are
        // quiet enough to stay in the background.
        if let lens = layout.lens {
            drawDish(around: lens, skin: skin, in: &context)
            drawLens(lens, skin: skin, in: &context)
        }
        if let speaker = layout.speaker {
            drawDish(around: speaker, skin: skin, in: &context)
            drawSpeaker(speaker, skin: skin, in: &context)
        }
        // The screens stay open: the picture lies below the case.
        context.blendMode = .destinationOut
        for screen in layout.screens {
            context.fill(Path(screen), with: .color(.black))
        }
        context.blendMode = .normal
    }

    /// The case: a gradient from top to bottom, light from above, and
    /// shade where it curves away at the sides and the bottom.
    private static func drawBody(_ bounds: CGRect, skin: ConsoleSkin, in context: inout GraphicsContext) {
        let all = Path(bounds)
        context.fill(all, with: .linearGradient(
            Gradient(colors: [skin.bodyTop, skin.bodyBottom]),
            startPoint: CGPoint(x: bounds.midX, y: bounds.minY), endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))
        context.fill(all, with: .radialGradient(
            Gradient(colors: [skin.bodyLight.opacity(skin.isLight ? 0.5 : 0.2), skin.bodyLight.opacity(0)]),
            center: CGPoint(x: bounds.midX, y: bounds.minY - bounds.height * 0.15),
            startRadius: 0, endRadius: bounds.height * 0.8))
        let side: CGFloat = 14
        let shade = skin.bodyShade.opacity(skin.isLight ? 0.13 : 0.22)
        let clear = skin.bodyShade.opacity(0)
        context.fill(Path(CGRect(x: bounds.minX, y: bounds.minY, width: side, height: bounds.height)), with: .linearGradient(
            Gradient(colors: [shade, clear]),
            startPoint: CGPoint(x: bounds.minX, y: 0), endPoint: CGPoint(x: bounds.minX + side, y: 0)))
        context.fill(Path(CGRect(x: bounds.maxX - side, y: bounds.minY, width: side, height: bounds.height)), with: .linearGradient(
            Gradient(colors: [clear, shade]),
            startPoint: CGPoint(x: bounds.maxX - side, y: 0), endPoint: CGPoint(x: bounds.maxX, y: 0)))
        let foot: CGFloat = 22
        context.fill(Path(CGRect(x: bounds.minX, y: bounds.maxY - foot, width: bounds.width, height: foot)), with: .linearGradient(
            Gradient(colors: [clear, skin.bodyShade.opacity(skin.isLight ? 0.18 : 0.3)]),
            startPoint: CGPoint(x: 0, y: bounds.maxY - foot), endPoint: CGPoint(x: 0, y: bounds.maxY)))
        let head: CGFloat = 8
        context.fill(Path(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: head)), with: .linearGradient(
            Gradient(colors: [skin.bodyLight.opacity(skin.isLight ? 0.9 : 0.28), skin.bodyLight.opacity(0)]),
            startPoint: CGPoint(x: 0, y: bounds.minY), endPoint: CGPoint(x: 0, y: bounds.minY + head)))
    }

    /// The hinge at the fold: the edge of one half curving down, a gap, the
    /// barrel with the light on it, a gap, and the edge of the other half.
    /// Flat, the barrel stands out less.
    private static func drawFold(_ hinge: CaseLayout.Hinge, skin: ConsoleSkin, in context: inout GraphicsContext) {
        let frame = hinge.frame
        let across = hinge.isHorizontal ? frame.height : frame.width
        guard across > 0 else { return }
        let depth: CGFloat = hinge.isBent ? 1 : 0.55
        let middle = skin.bodyTop.mix(with: skin.bodyBottom, by: 0.5)
        func barrel(_ color: Color) -> Color {
            hinge.isBent ? color : color.mix(with: middle, by: 0.45)
        }
        let lip = min(5, across * 0.14) / across
        let gap = min(1.5, across * 0.05) / across
        let groove = skin.bodyShade.opacity(skin.isLight ? 0.55 : 0.75)
        let gradient = Gradient(stops: [
            .init(color: skin.bodyShade.opacity(0), location: 0),
            .init(color: skin.bodyShade.opacity((skin.isLight ? 0.2 : 0.35) * depth), location: lip - gap),
            .init(color: groove, location: lip - gap),
            .init(color: groove, location: lip),
            .init(color: barrel(skin.hingeDark), location: lip),
            .init(color: barrel(skin.hingeLight), location: lip + (1 - 2 * lip) * 0.3),
            .init(color: barrel(skin.hingeMiddle), location: lip + (1 - 2 * lip) * 0.64),
            .init(color: barrel(skin.hingeDark), location: 1 - lip),
            .init(color: groove, location: 1 - lip),
            .init(color: groove, location: 1 - lip + gap),
            .init(color: skin.bodyLight.opacity((skin.isLight ? 0.9 : 0.3) * depth), location: 1 - lip + gap),
            .init(color: skin.bodyLight.opacity(0), location: 1),
        ])
        let start = hinge.isHorizontal ? CGPoint(x: frame.midX, y: frame.minY) : CGPoint(x: frame.minX, y: frame.midY)
        let end = hinge.isHorizontal ? CGPoint(x: frame.midX, y: frame.maxY) : CGPoint(x: frame.maxX, y: frame.midY)
        context.fill(Path(frame), with: .linearGradient(gradient, startPoint: start, endPoint: end))

        // The barrel has three parts; the seams between them show.
        let length = hinge.isHorizontal ? frame.width : frame.height
        let inset = lip * across
        for share in [0.3, 0.7] {
            let at = (hinge.isHorizontal ? frame.minX : frame.minY) + length * share
            let seam = hinge.isHorizontal
                ? CGRect(x: at - 0.75, y: frame.minY + inset, width: 1.5, height: across - 2 * inset)
                : CGRect(x: frame.minX + inset, y: at - 0.75, width: across - 2 * inset, height: 1.5)
            let light = hinge.isHorizontal ? seam.offsetBy(dx: 1.5, dy: 0) : seam.offsetBy(dx: 0, dy: 1.5)
            context.fill(Path(seam), with: .color(skin.bodyShade.opacity((skin.isLight ? 0.45 : 0.7) * depth)))
            context.fill(Path(light), with: .color(skin.bodyLight.opacity((skin.isLight ? 0.7 : 0.22) * depth)))
        }
    }

    /// The hinge of the console between two stacked screens: a barrel from
    /// L to R that stands out of the case.
    private static func drawBar(_ hinge: CaseLayout.Hinge, skin: ConsoleSkin, in context: inout GraphicsContext) {
        let frame = hinge.frame
        guard frame.width > 0, frame.height > 0 else { return }
        let path = RoundedRectangle(cornerRadius: min(6, frame.height / 2), style: .continuous).path(in: frame)
        // The groove it lies in, then its shadow on the case below it.
        context.fill(path.strokedPath(StrokeStyle(lineWidth: 3)), with: .color(skin.bodyShade.opacity(skin.isLight ? 0.3 : 0.6)))
        var lifted = context
        lifted.addFilter(.shadow(color: skin.bodyShade.opacity(skin.isLight ? 0.35 : 0.6), radius: 2, x: 0, y: 1.5))
        lifted.fill(path, with: .color(skin.hingeMiddle))
        context.fill(path, with: .linearGradient(
            Gradient(stops: [
                .init(color: skin.hingeMiddle, location: 0),
                .init(color: skin.hingeLight, location: 0.3),
                .init(color: skin.hingeMiddle, location: 0.66),
                .init(color: skin.hingeDark, location: 1),
            ]),
            startPoint: CGPoint(x: frame.midX, y: frame.minY), endPoint: CGPoint(x: frame.midX, y: frame.maxY)))
    }

    /// A bezel, set into the case: the case throws a shade on its upper
    /// edge and takes the light on the edge below it.
    private static func drawBezel(_ bezel: CaseLayout.Bezel, skin: ConsoleSkin, in context: inout GraphicsContext) {
        let frame = bezel.frame
        guard frame.width > 0, frame.height > 0 else { return }
        let left: CGFloat = bezel.endsAtLeftEdge ? 0 : 1
        let right: CGFloat = bezel.endsAtRightEdge ? 0 : 1
        let path = UnevenRoundedRectangle(
            topLeadingRadius: bezel.topCorner * left, bottomLeadingRadius: bezel.bottomCorner * left,
            bottomTrailingRadius: bezel.bottomCorner * right, topTrailingRadius: bezel.topCorner * right, style: .continuous
        ).path(in: frame)
        context.fill(path.offsetBy(dx: 0, dy: 1.25), with: .color(skin.bodyLight.opacity(skin.isLight ? 1 : 0.32)))
        context.fill(path.offsetBy(dx: 0, dy: -1), with: .color(skin.bodyShade.opacity(skin.isLight ? 0.35 : 0.6)))
        context.fill(path, with: .linearGradient(
            Gradient(colors: [skin.bezelTop, skin.bezelBottom]),
            startPoint: CGPoint(x: frame.midX, y: frame.minY), endPoint: CGPoint(x: frame.midX, y: frame.maxY)))
    }

    /// A dish of the case around something round that sits in it: a shade
    /// at its upper edge, the light on the edge below it.
    private static func drawDish(around hole: CGRect, skin: ConsoleSkin, in context: inout GraphicsContext) {
        let dish = hole.insetBy(dx: -ConsoleSkin.lensRing, dy: -ConsoleSkin.lensRing)
        let path = Path(ellipseIn: dish)
        context.fill(path.offsetBy(dx: 0, dy: 1), with: .color(skin.bodyLight.opacity(skin.isLight ? 0.9 : 0.22)))
        context.fill(path.offsetBy(dx: 0, dy: -0.75), with: .color(skin.bodyShade.opacity(skin.isLight ? 0.22 : 0.4)))
        context.fill(path, with: .linearGradient(
            Gradient(colors: [skin.bodyBottom.mix(with: skin.bodyShade, by: skin.isLight ? 0.08 : 0.2), skin.bodyTop.mix(with: skin.bodyBottom, by: 0.4)]),
            startPoint: CGPoint(x: dish.midX, y: dish.minY), endPoint: CGPoint(x: dish.midX, y: dish.maxY)))
    }

    /// The camera in its dish: black over the whole region the system
    /// reserves for it, as the system itself shows the camera. On the
    /// device the camera lies there; in the Simulator the system draws the
    /// same black disc at times, so the case looks the same either way.
    private static func drawLens(_ lens: CGRect, skin: ConsoleSkin, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: lens.offsetBy(dx: 0, dy: 0.75)), with: .color(skin.bodyLight.opacity(skin.isLight ? 0.8 : 0.2)))
        context.fill(Path(ellipseIn: lens), with: .color(.black))
    }

    /// The speaker: holes in its dish, in rings around its centre, in a
    /// tone of the case, so that it stays in the background.
    private static func drawSpeaker(_ speaker: CGRect, skin: ConsoleSkin, in context: inout GraphicsContext) {
        let radius = speaker.width / 2
        let hole = radius * 0.15
        let tone = skin.bodyBottom.mix(with: skin.bodyShade, by: skin.isLight ? 0.42 : 0.6)
        var centres = [CGPoint(x: speaker.midX, y: speaker.midY)]
        for (count, distance) in [(6, 0.34), (12, 0.68)] {
            for index in 0 ..< count {
                let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
                centres.append(CGPoint(x: speaker.midX + cos(angle) * radius * distance,
                                       y: speaker.midY + sin(angle) * radius * distance))
            }
        }
        for centre in centres {
            let rect = CGRect(x: centre.x - hole / 2, y: centre.y - hole / 2, width: hole, height: hole)
            context.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 0.6)), with: .color(skin.bodyLight.opacity(skin.isLight ? 0.8 : 0.2)))
            context.fill(Path(ellipseIn: rect), with: .color(tone))
        }
    }
}

extension PixelSize {
    /// The same size in points at `scale` pixels per point.
    nonisolated func points(scale: Int) -> CGSize {
        let s = CGFloat(max(1, scale))
        return CGSize(width: CGFloat(width) / s, height: CGFloat(height) / s)
    }
}
