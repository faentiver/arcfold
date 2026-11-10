import FoldLayout
import SwiftUI

/// The deck behind the touch controls that do not lie over a screen: a still
/// glow in the game's colour that fades out towards the bottom. Never under a
/// screen; static, so it costs nothing per frame. `GameStage` draws it in the
/// areas `DeckLayout` finds, one gradient over all of them.
struct ControlDeck: View {
    /// The parts of the view the deck covers, in its coordinates; nil for
    /// the whole view, as on the pages of the debug gallery.
    var areas: [CGRect]?

    @Environment(\.gameStyle) private var gameStyle
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let areas {
            if let bounds = areas.bounds {
                glow
                    .frame(width: bounds.width, height: bounds.height)
                    // One gradient for every area, cut to their union.
                    .mask {
                        Path { path in
                            for area in areas {
                                path.addRect(area.offsetBy(dx: -bounds.minX, dy: -bounds.minY))
                            }
                        }
                    }
                    .offset(x: bounds.minX, y: bounds.minY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            glow
                .ignoresSafeArea(edges: [.bottom, .trailing])
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var glow: some View {
        let strength = contrast == .increased ? 0.6 : 1
        // Fades in below the screens instead of starting at full strength,
        // which drew a hard edge across the whole width.
        return LinearGradient(
            stops: [
                .init(color: gameStyle.primary.opacity(0), location: 0),
                .init(color: gameStyle.primary.opacity(0.30 * strength), location: 0.08),
                .init(color: gameStyle.primary.opacity(0.12 * strength), location: 0.45),
                .init(color: gameStyle.primary.opacity(0), location: 0.75),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .background(.black)
    }
}

/// Where the deck lies in a layout (ADR 0007, rule R3): around every control
/// zone that lies over no screen, grown sideways and then up and down until
/// a screen, the fold or the edge of the view stops it. A pure function of
/// `GameLayout`, so tests check it against every pose. Controls over a screen
/// sit on the picture and have no deck; without touch controls there is none.
nonisolated enum DeckLayout {
    static func areas(of layout: GameLayout, in geometry: FoldGeometry) -> [PixelRect] {
        guard let zones = layout.controls else { return [] }
        let screens = layout.screens.map(\.destination)
        // The fold divides the device; the deck stays on either side of it.
        let fold = geometry.fold.flatMap { $0.isEmpty ? nil : $0 }
        let obstacles = screens + (fold.map { [$0] } ?? [])
        let bounds = geometry.bounds
        var areas: [PixelRect] = []
        for zone in zones.all where !zone.isEmpty && !screens.contains(where: { zone.intersects($0) }) {
            var left = bounds.minX
            var right = bounds.maxX
            for obstacle in obstacles where obstacle.minY < zone.maxY && obstacle.maxY > zone.minY {
                if obstacle.maxX <= zone.minX {
                    left = max(left, obstacle.maxX)
                } else if obstacle.minX >= zone.maxX {
                    right = min(right, obstacle.minX)
                }
            }
            var top = bounds.minY
            var bottom = bounds.maxY
            for obstacle in obstacles where obstacle.minX < right && obstacle.maxX > left {
                if obstacle.maxY <= zone.minY {
                    top = max(top, obstacle.maxY)
                } else if obstacle.minY >= zone.maxY {
                    bottom = min(bottom, obstacle.minY)
                }
            }
            let area = PixelRect(x: left, y: top, width: right - left, height: bottom - top)
            if !area.isEmpty, !areas.contains(area) {
                areas.append(area)
            }
        }
        return areas
    }
}

extension PixelSize {
    /// The same size in points at `scale` pixels per point.
    nonisolated func points(scale: Int) -> CGSize {
        let s = CGFloat(max(1, scale))
        return CGSize(width: CGFloat(width) / s, height: CGFloat(height) / s)
    }
}

extension Array where Element == CGRect {
    /// The smallest rectangle around all of them; nil for none.
    nonisolated var bounds: CGRect? {
        guard let first else { return nil }
        return dropFirst().reduce(first) { $0.union($1) }
    }
}

#Preview {
    ControlDeck()
        .frame(width: 382, height: 392)
        .environment(\.gameStyle, GameStyle(id: "1", name: "Selftest"))
}
