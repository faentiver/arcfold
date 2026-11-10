@testable import Arcfold
import SwiftUI
import Testing

/// The generated look of a game: the same file always looks the same, every
/// colour pair, pattern and corner occurs, and white stays readable on the
/// artwork and on pressed buttons (ADR 0007).
@MainActor
struct GameStyleTests {
    /// Styles for many ids in the format of `Game.id`.
    static let styles: [GameStyle] = (0..<400).map { index in
        let id = GameStyle.bytes(of: "game \(index)").map { String(format: "%02x", $0) }.joined()
        return GameStyle(id: id, name: "Game \(index)")
    }

    @Test func theSameIdGivesTheSameStyle() {
        let id = "8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4"
        #expect(GameStyle(id: id, name: "selftest") == GameStyle(id: id, name: "selftest"))
        let style = GameStyle(id: id, name: "selftest")
        // Byte 0 0x8f = 143 → pair 3, byte 1 0x43 = 67 → stripes, byte 2 0x43 → bottom leading.
        #expect(style.paletteIndex == 3)
        #expect(style.pattern == .stripes)
        #expect(style.corner == .bottomLeading)
        #expect(style.seed == 0x4664_8F6B_96DF_89DD)
    }

    @Test func idsThatAreNoHashAreHashedFirst() {
        #expect(GameStyle.bytes(of: "1").count == 32)
        #expect(GameStyle.bytes(of: "1") == GameStyle.bytes(of: "1"))
        #expect(GameStyle.bytes(of: "1") != GameStyle.bytes(of: "2"))
        // 64 characters, but not hex
        #expect(GameStyle.bytes(of: String(repeating: "z", count: 64)).count == 32)
    }

    @Test func everyPairPatternAndCornerOccurs() {
        #expect(Set(Self.styles.map(\.paletteIndex)) == Set(GameStyle.palette.indices))
        #expect(Set(Self.styles.map(\.pattern)) == Set(GameStyle.Pattern.allCases))
        #expect(Set(Self.styles.map(\.corner)) == Set(GameStyle.Corner.allCases))
    }

    @Test(arguments: [
        ("selftest", "S"), ("Homebrew Demo", "HD"), ("fold_runner", "FR"), ("arc-light", "AL"),
        ("  two   spaces  ", "TS"), ("星の旅", "星"), ("2048", "2"), ("éclair rouge", "ÉR"), ("👾 Invaders", "👾I"),
    ])
    func theMonogramTakesTheFirstLettersOfTwoWords(name: String, monogram: String) {
        #expect(GameStyle.monogram(of: name, fallback: "GBA") == monogram)
    }

    @Test func anEmptyNameShowsTheSystem() {
        #expect(GameStyle.monogram(of: "", fallback: "GBA") == "GBA")
        #expect(GameStyle.monogram(of: " - ", fallback: "GBA") == "GBA")
    }

    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func whiteReadsOnTheMonogramCornerAndOnPressedButtons(scheme: ColorScheme) throws {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        for index in GameStyle.palette.indices {
            let style = try #require(Self.styles.first { $0.paletteIndex == index })
            let corner = Self.contrastOfWhite(on: style.monogramCorner.resolve(in: environment))
            let pressed = Self.contrastOfWhite(on: style.pressedFill.resolve(in: environment))
            #expect(corner >= 3, "pair \(index), \(scheme): white on the monogram corner \(corner)")
            #expect(pressed >= 3, "pair \(index), \(scheme): white on a pressed button \(pressed)")
        }
    }

    /// WCAG contrast of white against an opaque colour.
    static func contrastOfWhite(on color: Color.Resolved) -> Double {
        let luminance = 0.2126 * Double(color.linearRed) + 0.7152 * Double(color.linearGreen)
            + 0.0722 * Double(color.linearBlue)
        return 1.05 / (luminance + 0.05)
    }
}

/// The dimming plate beneath in-game glass (docs/wissen/oberflaeche.md):
/// light over the still deck, dark over the picture, and the same with
/// Increase Contrast and Reduce Transparency wherever it lies.
struct GamePlateTests {
    @Test(arguments: [false, true])
    func theDeckGetsALighterPlate(isSmallLabel: Bool) {
        let picture = GamePlate.look(isSmallLabel: isSmallLabel, backdrop: .picture, increasedContrast: false,
                                     reduceTransparency: false, showsBorders: false)
        let deck = GamePlate.look(isSmallLabel: isSmallLabel, backdrop: .deck, increasedContrast: false,
                                  reduceTransparency: false, showsBorders: false)
        #expect(picture.plateOpacity == (isSmallLabel ? 0.80 : 0.70))
        #expect(deck.plateOpacity == (isSmallLabel ? 0.45 : 0.35))
        #expect(deck.borderWidth == 0 && picture.borderWidth == 0)
    }

    @Test(arguments: [false, true])
    func increasedContrastAndReducedTransparencyKeepTheirPlates(isSmallLabel: Bool) {
        for backdrop in [GlassBackdrop.picture, .deck] {
            let contrast = GamePlate.look(isSmallLabel: isSmallLabel, backdrop: backdrop, increasedContrast: true,
                                          reduceTransparency: false, showsBorders: false)
            #expect(contrast.plateOpacity == (isSmallLabel ? 0.90 : 0.80))
            // Over the picture the edge has to stand out by itself.
            #expect(contrast.borderWidth == 1 && contrast.borderOpacity == (backdrop == .picture ? 0.90 : 0.35))
            let borders = GamePlate.look(isSmallLabel: isSmallLabel, backdrop: backdrop, increasedContrast: false,
                                         reduceTransparency: false, showsBorders: true)
            #expect(borders.borderWidth == 1 && borders.borderOpacity == 0.35)
            let solid = GamePlate.look(isSmallLabel: isSmallLabel, backdrop: backdrop, increasedContrast: false,
                                       reduceTransparency: true, showsBorders: false)
            #expect(solid.plateOpacity == (isSmallLabel ? 0.90 : 0.85))
        }
    }

    /// With Increase Contrast a key over the picture keeps its boundary at
    /// 3 : 1 against a picture of any brightness: the white edge against a
    /// dark picture, the plate against a light one. Reckoned for grey
    /// pictures, with the plate and the edge blended over them as the view
    /// draws them; at 0.35 the edge left a gap down to 1.7 : 1 in between.
    @Test(arguments: [false, true])
    func theEdgeOverThePictureStandsOutFromAnyPicture(isSmallLabel: Bool) {
        func luminance(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func contrast(_ one: Double, _ other: Double) -> Double {
            let (light, dark) = (max(luminance(one), luminance(other)), min(luminance(one), luminance(other)))
            return (light + 0.05) / (dark + 0.05)
        }
        func weakest(_ look: GamePlate.Look) -> Double {
            (0...255).map { step in
                let picture = Double(step) / 255
                let plate = 0.15 * look.plateOpacity + picture * (1 - look.plateOpacity)
                let edge = look.borderOpacity + plate * (1 - look.borderOpacity)
                return max(contrast(edge, picture), contrast(plate, picture))
            }.min() ?? 0
        }
        let look = GamePlate.look(isSmallLabel: isSmallLabel, backdrop: .picture, increasedContrast: true,
                                  reduceTransparency: false, showsBorders: false)
        #expect(weakest(look) >= 3, "the edge at \(look.borderOpacity) falls to \(weakest(look)) : 1")
        var old = look
        old.borderOpacity = GamePlate.borderOpacity
        #expect(weakest(old) < 2)
    }
}
