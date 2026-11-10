import CryptoKit
import SwiftUI

/// The look of a game without a cover, from its id and name only: a pair of
/// system colours, a pattern, the corner it starts from and a monogram.
/// A pure value, so previews, tests, the library and the game screen agree.
/// Arcfold never ships or loads covers (hard rules in CLAUDE.md).
nonisolated struct GameStyle: Hashable, Sendable {
    enum Pattern: CaseIterable, Sendable, Hashable {
        case arcs
        case folds
        case pixels
        case stripes
    }

    /// Where arcs start, and which way folds and stripes run.
    enum Corner: CaseIterable, Sendable, Hashable {
        case topLeading
        case topTrailing
        case bottomTrailing
        case bottomLeading
    }

    /// One entry of the palette: system colours only, so light, dark and
    /// Increase Contrast come from the system. Light base colours are darkened
    /// so a white monogram reads on them; yellow is left out for that reason.
    struct Pair: Sendable, Hashable {
        var base: Color
        var second: Color
        var darkening: Double
    }

    static let palette: [Pair] = [
        Pair(base: .red, second: .orange, darkening: 0.05),
        Pair(base: .orange, second: .pink, darkening: 0.18),
        Pair(base: .brown, second: .orange, darkening: 0.10),
        Pair(base: .green, second: .teal, darkening: 0.25),
        Pair(base: .mint, second: .green, darkening: 0.35),
        Pair(base: .teal, second: .cyan, darkening: 0.30),
        Pair(base: .blue, second: .teal, darkening: 0.05),
        Pair(base: .indigo, second: .blue, darkening: 0),
        Pair(base: .purple, second: .indigo, darkening: 0),
        Pair(base: .pink, second: .purple, darkening: 0.05),
    ]

    /// The darkening of every second colour.
    static let secondDarkening = 0.12

    var paletteIndex: Int
    var primary: Color
    var secondary: Color
    var pattern: Pattern
    var corner: Corner
    var monogram: String
    /// Moves the inner points of the mesh.
    var seed: UInt64

    /// Byte 0 of the id picks the colour pair, byte 1 the pattern, byte 2 the
    /// corner, bytes 3 to 10 the seed. An id that is no SHA-256 in hex (the
    /// previews use "1", "2") is hashed with SHA-256 first. Never `hashValue`:
    /// it changes from launch to launch.
    init(id: String, name: String, systemName: String = "") {
        let bytes = Self.bytes(of: id)
        paletteIndex = Int(bytes[0]) % Self.palette.count
        let pair = Self.palette[paletteIndex]
        primary = pair.base.mix(with: .black, by: pair.darkening)
        secondary = pair.second.mix(with: .black, by: Self.secondDarkening)
        pattern = Pattern.allCases[Int(bytes[1]) % Pattern.allCases.count]
        corner = Corner.allCases[Int(bytes[2]) % Corner.allCases.count]
        seed = bytes[3...10].reduce(0) { $0 << 8 | UInt64($1) }
        monogram = Self.monogram(of: name, fallback: systemName)
    }

    init(_ game: Game) {
        self.init(id: game.id, name: game.name,
                  systemName: GameSystem.system(id: game.system)?.name ?? game.system.uppercased())
    }

    /// Outside a game, and in previews without one.
    static let placeholder = GameStyle(id: "", name: "")

    /// A pressed touch button and the pressed sector of the direction pad:
    /// the base colour, a little darker, so white keeps its contrast.
    var pressedFill: Color {
        primary.mix(with: .black, by: 0.15)
    }

    /// The corner under the monogram, the darkest part of the artwork's base.
    var monogramCorner: Color {
        primary.mix(with: .black, by: 0.28)
    }

    /// The 32 bytes of the id, or of its SHA-256 if it is no 64-digit hex string.
    static func bytes(of id: String) -> [UInt8] {
        let utf8 = Array(id.utf8)
        if utf8.count == 64 {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(32)
            var index = 0
            while index < 64, let high = hexValue(utf8[index]), let low = hexValue(utf8[index + 1]) {
                bytes.append(high << 4 | low)
                index += 2
            }
            if bytes.count == 32 {
                return bytes
            }
        }
        return Array(SHA256.hash(data: utf8))
    }

    private static func hexValue(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// The first letters of the first two words (split at white space, "-"
    /// and "_"), else the first letter, upper case. Characters, not bytes, so
    /// emoji, CJK and digits work. An empty name gives `fallback`.
    static func monogram(of name: String, fallback: String) -> String {
        let words = name.split { $0.isWhitespace || $0 == "-" || $0 == "_" }
        guard let first = words.first?.first else { return fallback }
        var letters = String(first)
        if words.count > 1, let second = words[1].first {
            letters.append(second)
        }
        return letters.uppercased()
    }
}

extension EnvironmentValues {
    /// The style of the running game; set where the game screen is presented.
    @Entry var gameStyle: GameStyle = .placeholder
}
