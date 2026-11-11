import SwiftUI

/// The generated artwork of a game: a mesh gradient in the game's colours, a
/// pattern and the monogram. Content, so it never carries glass (rule R1).
/// No covers: the look comes from the file's hash alone.
struct GameArtwork: View {
    enum Variant: Hashable {
        /// A library tile with the corner radius of the width class: 4 : 3,
        /// or as wide as its column and `height` high where the grid names
        /// one, because the window is too low for 4 : 3.
        case tile(corner: CGFloat, height: CGFloat? = nil)
        /// The head of the pause menu, 56 × 42.
        case thumbnail
        /// Behind the loading spinner and the failure message: blurred and
        /// dimmed, without monogram.
        case backdrop
    }

    let variant: Variant
    private let explicitStyle: GameStyle?

    @Environment(\.gameStyle) private var environmentStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    static let thumbnailSize = CGSize(width: 56, height: 42)

    /// The artwork of `style`, or of the game in the environment.
    init(style: GameStyle? = nil, variant: Variant) {
        explicitStyle = style
        self.variant = variant
    }

    private var style: GameStyle {
        explicitStyle ?? environmentStyle
    }

    var body: some View {
        switch variant {
        case let .tile(corner, height):
            Group {
                if let height {
                    framed(corner: corner)
                        .frame(height: height)
                } else {
                    framed(corner: corner)
                        .aspectRatio(4 / 3, contentMode: .fit)
                }
            }
            .modifier(ArtworkAccessibility())
        case .thumbnail:
            framed(corner: 8)
                .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                .modifier(ArtworkAccessibility())
        case .backdrop:
            ZStack {
                mesh
                pattern
            }
            .blur(radius: 40)
            // Dark enough for the system's secondary text of the failure
            // message: at 0.45 it measured 3.8 : 1 over selftest's colours.
            .overlay(Color.black.opacity(0.65))
            .clipped()
            .modifier(ArtworkAccessibility())
        }
    }

    private func framed(corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            mesh
            pattern
            // Drawn, not laid out as text: decoration that the tile's name
            // already says, so it is no accessibility element.
            Canvas { context, size in
                guard size.width >= 40 else { return }
                let monogram = context.resolve(
                    Text(verbatim: style.monogram)
                        .font(.system(size: size.height * 0.46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94)))
                context.addFilter(.shadow(color: .black.opacity(0.22), radius: 6, y: 3))
                context.draw(monogram, at: CGPoint(x: size.width * 0.07, y: size.height - size.width * 0.04),
                             anchor: .bottomLeading)
            }
        }
        .clipShape(shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(.separator, lineWidth: 1)
            } else {
                shape.strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                                   lineWidth: 0.5)
            }
        }
    }

    /// Fixed corners, edge midpoints moved by up to 0.1 and the centre by up
    /// to 0.15, all from the seed.
    private var mesh: some View {
        var random = SplitMix64(seed: style.seed)
        func jitter(_ amount: Float) -> Float {
            (Float(random.next() % 10_000) / 10_000 * 2 - 1) * amount
        }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + jitter(0.1), 0], [1, 0],
            [0, 0.5 + jitter(0.1)], [0.5 + jitter(0.15), 0.5 + jitter(0.15)], [1, 0.5 + jitter(0.1)],
            [0, 1], [0.5 + jitter(0.1), 1], [1, 1],
        ]
        let middle = style.primary.mix(with: style.secondary, by: 0.5)
        let colors: [Color] = [
            style.primary.mix(with: .white, by: 0.12), style.primary, middle,
            style.primary, middle, style.secondary,
            style.monogramCorner, style.secondary, style.secondary.mix(with: .black, by: 0.38),
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }

    private var pattern: some View {
        let strength = contrast == .increased ? 0.08 : 0.16
        return Canvas { context, size in
            ArtworkPattern(pattern: style.pattern, corner: style.corner, size: size).draw(in: &context)
        }
        .opacity(strength)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

private struct ArtworkAccessibility: ViewModifier {
    func body(content: Content) -> some View {
        content
            .accessibilityHidden(true)
            .accessibilityIgnoresInvertColors()
    }
}

/// The white lines of one pattern, drawn once per tile.
private struct ArtworkPattern {
    let pattern: GameStyle.Pattern
    let corner: GameStyle.Corner
    let size: CGSize

    /// The corner as a point, and the directions towards the opposite corner.
    private var origin: CGPoint {
        switch corner {
        case .topLeading: .zero
        case .topTrailing: CGPoint(x: size.width, y: 0)
        case .bottomTrailing: CGPoint(x: size.width, y: size.height)
        case .bottomLeading: CGPoint(x: 0, y: size.height)
        }
    }

    private var signX: CGFloat { origin.x == 0 ? 1 : -1 }
    private var signY: CGFloat { origin.y == 0 ? 1 : -1 }

    func draw(in context: inout GraphicsContext) {
        let width = size.width
        let white = GraphicsContext.Shading.color(.white)
        switch pattern {
        case .arcs:
            var path = Path()
            let step = width * 0.13
            var radius = step
            let reach = hypot(size.width, size.height)
            while radius < reach {
                path.addEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: 2 * radius, height: 2 * radius))
                radius += step
            }
            context.stroke(path, with: white, lineWidth: width * 0.018)
        case .folds:
            var path = Path()
            let step = size.height * 0.2
            let tooth = width / 6
            var y = signY > 0 ? step / 2 : size.height - step / 2
            while y >= -step, y <= size.height + step {
                path.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                var up = true
                while x < width {
                    x += tooth
                    path.addLine(to: CGPoint(x: x, y: y + (up ? -1 : 1) * step * 0.3 * signX))
                    up.toggle()
                }
                y += step * signY
            }
            context.stroke(path, with: white, style: StrokeStyle(lineWidth: width * 0.018, lineJoin: .round))
        case .pixels:
            var path = Path()
            let grid = width * 0.1
            let square = width * 0.04
            let columns = Int(width / grid) + 1
            let rows = Int(size.height / grid) + 1
            for row in 0..<rows {
                for column in 0..<columns where row + column < max(columns, rows) * 2 / 3 {
                    let x = origin.x + signX * (CGFloat(column) * grid + (grid - square) / 2) - (signX < 0 ? square : 0)
                    let y = origin.y + signY * (CGFloat(row) * grid + (grid - square) / 2) - (signY < 0 ? square : 0)
                    path.addRect(CGRect(x: x, y: y, width: square, height: square))
                }
            }
            context.fill(path, with: white)
        case .stripes:
            var path = Path()
            let step = width * 0.09
            let span = size.width + size.height
            var offset: CGFloat = -span
            // The stripes run across the diagonal through the corner.
            let rising = signX == signY
            while offset < span {
                if rising {
                    path.move(to: CGPoint(x: offset, y: size.height))
                    path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                } else {
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                }
                offset += step
            }
            context.stroke(path, with: white, lineWidth: width * 0.028)
        }
    }
}

/// A small, fixed random generator, so the same seed moves the mesh the
/// same way on every launch.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview("Tiles") {
    let names = ["Selftest", "Homebrew Demo", "Pixel Quest", "fold_runner", "Arc-Light", "星", "2048", "Night Drive"]
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 20) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                GameArtwork(style: GameStyle(id: "\(index)", name: name), variant: .tile(corner: 14))
            }
        }
        .padding(16)
    }
}

#Preview("Thumbnail and backdrop") {
    ZStack {
        GameArtwork(style: GameStyle(id: "1", name: "Selftest"), variant: .backdrop)
        GameArtwork(style: GameStyle(id: "1", name: "Selftest"), variant: .thumbnail)
    }
}
