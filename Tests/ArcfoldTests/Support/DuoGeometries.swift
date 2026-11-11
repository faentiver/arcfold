@testable import Arcfold
import FoldLayout

/// The geometries the layouts of M2 are tested with (`LayoutInvariantTests`
/// and `GameLayoutTests` in FoldLayout, ADR 0006), for the tests of the glass
/// interface on top of them (ADR 0007): the closed Duo with the bar at the
/// side and on top, sideways, an iPhone without a hinge, the plan's
/// tabletop, a camera in a lower corner, and folds across and down of 0,
/// 16, 32 and 64 pt, with and without margins, active and inactive.
enum DuoGeometries {
    struct Case: Sendable, CustomStringConvertible {
        let name: String
        let geometry: FoldGeometry
        var description: String { name }
    }

    static let scale = 3
    /// The outer display, 466 × 678 pt.
    static let outer = PixelSize(width: 1398, height: 2034)
    static let outerLandscape = PixelSize(width: 2034, height: 1398)
    /// The inner display held upright (the fold across), 669 × 951 pt.
    static let inner = PixelSize(width: 2007, height: 2853)
    /// The inner display held like a book (the fold from top to bottom), 951 × 669 pt.
    static let innerLandscape = PixelSize(width: 2853, height: 2007)

    static func closed(barOnTop: Bool) -> FoldGeometry {
        FoldGeometry(container: outer,
                     safeArea: barOnTop ? PixelInsets(top: 82 * 3, bottom: 34 * 3) : PixelInsets(bottom: 34 * 3, right: 84 * 3),
                     scale: scale)
    }

    static func foldAcross(_ container: PixelSize = inner, band: Int, margin: Int = 0, active: Bool) -> FoldGeometry {
        let height = (band + 2 * margin) * scale
        let fold = PixelRect(x: 0, y: (container.height - height) / 2, width: container.width, height: height)
        return FoldGeometry(container: container, fold: fold, foldMargins: PixelInsets(top: margin * scale, bottom: margin * scale),
                            isFoldActive: active, scale: scale)
    }

    static func foldDown(_ container: PixelSize = innerLandscape, band: Int, margin: Int = 0, active: Bool) -> FoldGeometry {
        let width = (band + 2 * margin) * scale
        let fold = PixelRect(x: (container.width - width) / 2, y: 0, width: width, height: container.height)
        return FoldGeometry(container: container, fold: fold, foldMargins: PixelInsets(left: margin * scale, right: margin * scale),
                            isFoldActive: active, scale: scale)
    }

    /// Every case of `LayoutInvariantTests` in FoldLayout.
    static let cases: [Case] = {
        var all = [
            Case(name: "closed, bar at the side", geometry: closed(barOnTop: false)),
            Case(name: "closed, bar on top", geometry: closed(barOnTop: true)),
            Case(name: "closed, sideways", geometry: FoldGeometry(container: outerLandscape)),
            Case(name: "closed, sideways with the bar",
                 geometry: FoldGeometry(container: outerLandscape, safeArea: PixelInsets(bottom: 63, right: 252))),
            Case(name: "iPhone upright", geometry: FoldGeometry(
                container: PixelSize(width: 1206, height: 2622), safeArea: PixelInsets(top: 186, bottom: 102))),
            Case(name: "iPhone sideways", geometry: FoldGeometry(
                container: PixelSize(width: 2622, height: 1206), safeArea: PixelInsets(left: 186, bottom: 63, right: 186))),
            Case(name: "plan, tabletop", geometry: FoldGeometry(
                container: PixelSize(width: 1878, height: 2670), fold: PixelRect(x: 0, y: 1335, width: 1878, height: 0),
                isFoldActive: true)),
            Case(name: "book with a camera", geometry: {
                var geometry = foldDown(band: 16, active: true)
                geometry.occlusions = [PixelRect(x: 2600, y: 1800, width: 253, height: 207)]
                return geometry
            }()),
            Case(name: "tabletop with a camera", geometry: {
                var geometry = foldAcross(band: 16, active: true)
                geometry.occlusions = [PixelRect(x: 1750, y: 2600, width: 257, height: 253)]
                return geometry
            }()),
        ]
        for band in [0, 16, 32, 64] {
            for margin in [0, 8] {
                for active in [false, true] {
                    let state = "\(band) pt, margins \(margin) pt, \(active ? "active" : "inactive")"
                    all.append(Case(name: "fold across \(state)", geometry: foldAcross(band: band, margin: margin, active: active)))
                    all.append(Case(name: "fold down \(state)", geometry: foldDown(band: band, margin: margin, active: active)))
                }
            }
        }
        return all
    }()

    /// The systems with their screens and buttons.
    static let systems: [(name: String, system: GameSystem)] = [("GBA", .gba), ("DS", .ds)]

    /// A system in one of the six poses as the Simulator reports them
    /// (measured with the screenshot tour): the view, the safe area and the
    /// division region of 121 px with margins of 20 pt.
    struct Pose: Sendable, CustomStringConvertible {
        let name: String
        let system: GameSystem
        let geometry: FoldGeometry
        var description: String { "\(system == .ds ? "DS" : "GBA") \(name)" }
    }

    /// The inner display in a real pose: sideways the fold runs from top to
    /// bottom (open and the book), upright across (flat and tabletop).
    static func measuredInner(sideways: Bool, active: Bool) -> FoldGeometry {
        sideways
            ? FoldGeometry(container: innerLandscape, safeArea: PixelInsets(bottom: 102),
                           fold: PixelRect(x: 1366, y: 0, width: 121, height: innerLandscape.height),
                           foldMargins: PixelInsets(left: 60, right: 60), isFoldActive: active, scale: scale)
            : FoldGeometry(container: inner, safeArea: PixelInsets(bottom: 102),
                           fold: PixelRect(x: 0, y: 1366, width: inner.width, height: 121),
                           foldMargins: PixelInsets(top: 60, bottom: 60), isFoldActive: active, scale: scale)
    }

    /// The GBA moves the vertical bar of the outer display to the top, the DS
    /// keeps it at the side (ADR 0006, section 7).
    static let measuredPoses: [Pose] = [GameSystem.gba, .ds].flatMap { system -> [Pose] in
        let barOnTop = system == .gba
        let sideways = FoldGeometry(
            container: outerLandscape,
            safeArea: barOnTop ? PixelInsets(top: 246, bottom: 102) : PixelInsets(left: 252, bottom: 102), scale: scale)
        return [
            Pose(name: "closed", system: system, geometry: closed(barOnTop: barOnTop)),
            Pose(name: "closed sideways", system: system, geometry: sideways),
            Pose(name: "open", system: system, geometry: measuredInner(sideways: true, active: false)),
            Pose(name: "book", system: system, geometry: measuredInner(sideways: true, active: true)),
            Pose(name: "tabletop", system: system, geometry: measuredInner(sideways: false, active: true)),
            Pose(name: "flat upright", system: system, geometry: measuredInner(sideways: false, active: false)),
        ]
    }
}
