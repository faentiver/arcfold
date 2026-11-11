import Foundation
import Testing
import UIKit

/// The accent colour and the app icon reach the app bundle (ADR 0007): the
/// asset catalog compiler writes both names into the Info.plist. White stays
/// readable on the accent in every appearance.
@MainActor
struct DesignAssetsTests {
    /// The key sits in CFBundleIcons > CFBundlePrimaryIcon, not at the top level.
    @Test func theAppIconComesFromTheIconComposerFile() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }

    @Test func theAccentColorIsTheAssetCatalogColor() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSAccentColorName") as? String == "AccentColor")
        #expect(UIColor(named: "AccentColor", in: .main, compatibleWith: nil) != nil)
    }

    /// White labels on prominent buttons (Resume, Close, Import Games) need
    /// 4.5 : 1. systemIndigo gives 3.5 : 1 in dark mode and 2.1 : 1 with
    /// Increase Contrast, so dark mode takes the light values of systemIndigo;
    /// light mode stays the system colour (ADR 0007).
    @Test(arguments: [
        (UIUserInterfaceStyle.light, UIAccessibilityContrast.normal), (.light, .high), (.dark, .normal), (.dark, .high),
    ])
    func whiteReadsOnTheAccent(style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast) throws {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.accessibilityContrast = contrast
        }
        let accent = try #require(UIColor(named: "AccentColor", in: .main, compatibleWith: nil))
        let ratio = Self.contrastOfWhite(on: accent.resolvedColor(with: traits))
        #expect(ratio >= 4.5, "white on the accent: \(ratio) : 1")
        if style == .light {
            // Light mode is the system colour itself.
            #expect(Self.components(of: accent.resolvedColor(with: traits))
                .elementsEqual(Self.components(of: UIColor.systemIndigo.resolvedColor(with: traits))) { abs($0 - $1) < 0.003 })
        }
    }

    static func components(of color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }

    /// WCAG contrast of white against an opaque colour.
    static func contrastOfWhite(on color: UIColor) -> Double {
        let rgb = components(of: color)
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
        return 1.05 / (luminance + 0.05)
    }
}
