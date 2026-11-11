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
            Case(name: "measured: closed, sideways, bar on top", geometry: closedSideways(barOnTop: true)),
            Case(name: "measured: closed, sideways, bar at the side", geometry: closedSideways(barOnTop: false)),
            Case(name: "measured: open", geometry: measuredInner(sideways: true, active: false)),
            Case(name: "measured: book", geometry: measuredInner(sideways: true, active: true)),
            Case(name: "measured: flat upright", geometry: measuredInner(sideways: false, active: false)),
            Case(name: "measured: tabletop", geometry: measuredInner(sideways: false, active: true)),
            Case(name: "fold at the lower edge, active", geometry: foldAtTheLowerEdge(active: true)),
            Case(name: "fold at the lower edge, inactive", geometry: foldAtTheLowerEdge(active: false)),
        ]
        for phone in iPhones {
            all.append(Case(name: "\(phone.name) upright", geometry: phone.upright))
            all.append(Case(name: "\(phone.name) sideways", geometry: phone.sideways))
        }
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

    /// A part of the inner display, 669 × 475 pt, whose lower edge is the
    /// fold: the side below the fold is empty.
    static func foldAtTheLowerEdge(active: Bool) -> FoldGeometry {
        FoldGeometry(container: PixelSize(width: 2007, height: 1425), fold: PixelRect(x: 0, y: 1366, width: 2007, height: 59),
                     isFoldActive: active, scale: scale)
    }

    /// An iPhone without a hinge, in points: its size held upright, and the
    /// inset of the camera at the top (upright) or at the sides (sideways);
    /// the home indicator takes 34 pt upright and 21 pt sideways.
    struct Phone: Sendable {
        let name: String
        let width: Int
        let height: Int
        let camera: Int

        var upright: FoldGeometry {
            FoldGeometry(container: PixelSize(width: width * 3, height: height * 3),
                         safeArea: PixelInsets(top: camera * 3, bottom: 34 * 3), scale: 3)
        }

        var sideways: FoldGeometry {
            FoldGeometry(container: PixelSize(width: height * 3, height: width * 3),
                         safeArea: PixelInsets(left: camera * 3, bottom: 21 * 3, right: camera * 3), scale: 3)
        }
    }

    /// The sizes of current iPhones, from the smallest to the largest, as
    /// in `LayoutInvariantTests`.
    static let iPhones = [
        Phone(name: "iPhone 375 × 812", width: 375, height: 812, camera: 44),
        Phone(name: "iPhone 393 × 852", width: 393, height: 852, camera: 59),
        Phone(name: "iPhone 402 × 874", width: 402, height: 874, camera: 62),
        Phone(name: "iPhone 430 × 932", width: 430, height: 932, camera: 59),
        Phone(name: "iPhone 440 × 956", width: 440, height: 956, camera: 62),
    ]

    /// Every case with both systems, as poses, for the tests that run over
    /// every geometry.
    static let everyPose: [Pose] = cases.flatMap { testCase in
        systems.map { Pose(name: testCase.name, system: $0.system, geometry: testCase.geometry) }
    }

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

    /// The camera of the outer display and the status area around it, as
    /// the Simulator reports them upright with the bar on top: 37 × 37 pt
    /// at (399.67, 29.33) and 84 × 82 pt in the corner.
    static let outerOcclusions = [PixelRect(x: 1199, y: 88, width: 111, height: 111), PixelRect(x: 1146, y: 0, width: 252, height: 246)]

    /// The closed device turned sideways: the bar on top, 82 pt, or at the
    /// leading edge, 84 pt, and the home indicator, 34 pt.
    static func closedSideways(barOnTop: Bool) -> FoldGeometry {
        FoldGeometry(container: outerLandscape,
                     safeArea: barOnTop ? PixelInsets(top: 246, bottom: 102) : PixelInsets(left: 252, bottom: 102), scale: scale)
    }

    /// Both systems move the vertical bar of the outer display to the top,
    /// so that the console stands in the middle of the display (ADR 0006,
    /// section 7; ADR 0007).
    static let measuredPoses: [Pose] = [GameSystem.gba, .ds].flatMap { system -> [Pose] in
        [
            Pose(name: "closed", system: system, geometry: closed(barOnTop: true)),
            Pose(name: "closed sideways", system: system, geometry: closedSideways(barOnTop: true)),
            Pose(name: "open", system: system, geometry: measuredInner(sideways: true, active: false)),
            Pose(name: "book", system: system, geometry: measuredInner(sideways: true, active: true)),
            Pose(name: "tabletop", system: system, geometry: measuredInner(sideways: false, active: true)),
            Pose(name: "flat upright", system: system, geometry: measuredInner(sideways: false, active: false)),
        ]
    }

    /// The DS for whoever prefers larger screens: it keeps the vertical bar
    /// at the side, and its case is slim (`ConsoleSkin.prefersLargerScreens`).
    static let largerScreenPoses: [Pose] = [
        Pose(name: "closed, larger screens", system: .ds, geometry: closed(barOnTop: false)),
        Pose(name: "closed sideways, larger screens", system: .ds, geometry: closedSideways(barOnTop: false)),
    ]
}
