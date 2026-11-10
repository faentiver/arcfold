#if DEBUG
import FoldLayout
import LibretroKit
import Renderer
import SwiftUI

/// Sample data for previews. Previews create no EmulationSession and no
/// InputState: the picture is a test pattern in a mailbox, the measurements
/// are fixed snapshots.
enum PreviewContent {
    static let geometry = VideoGeometry(baseWidth: 240, baseHeight: 160, maxWidth: 240, maxHeight: 160, aspectRatio: 1.5)

    static let systemInfo = SystemInfo(
        libraryName: "mGBA", libraryVersion: "0.10.5", validExtensions: ["gba"],
        needsFullPath: false, blocksExtract: false)

    /// A mailbox holding one RGB565 test pattern, due at once: eight colour
    /// bars over a grey ramp, with a white frame around the edge.
    static func mailboxWithTestPattern() -> FrameMailbox {
        let mailbox = FrameMailbox(geometry: geometry, format: .rgb565)
        let width = geometry.baseWidth
        let height = geometry.baseHeight
        let bars: [UInt16] = [0xFFFF, 0xFFE0, 0x07FF, 0x07E0, 0xF81F, 0xF800, 0x001F, 0x0000]
        var pixels = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt16
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                    value = 0xFFFF
                } else if y < height * 2 / 3 {
                    value = bars[x * bars.count / width]
                } else {
                    let level = UInt16(x * 31 / (width - 1))
                    value = level << 11 | (level << 1) << 5 | level
                }
                pixels[y * width + x] = value
            }
        }
        mailbox.submit(pixels: pixels.span.bytes, width: width, height: height, bytesPerRow: width * 2,
                       format: .rgb565, stamp: FrameStamp(sequence: 1, nominalTime: 0))
        return mailbox
    }

    /// The DS test pattern (ADR 0006, section 15): one XRGB8888 frame of
    /// 256 × 384 like melonDS DS delivers, both screens in their own colour
    /// with a white frame around each, and marker pixels at known places.
    enum DSPattern {
        static let width = 256
        static let height = 384
        /// Red, green, blue of each part.
        static let upperColor: (UInt8, UInt8, UInt8) = (0x30, 0x60, 0xC0)
        static let lowerColor: (UInt8, UInt8, UInt8) = (0x30, 0xA0, 0x50)
        static let frameColor: (UInt8, UInt8, UInt8) = (0xFF, 0xFF, 0xFF)
        static let upperMarkerColor: (UInt8, UInt8, UInt8) = (0xFF, 0x00, 0x00)
        static let lowerMarkerColor: (UInt8, UInt8, UInt8) = (0xFF, 0xFF, 0x00)
        /// Marker pixels in the coordinates of each screen, clear of the
        /// corners where L and R and the debug overlay may lie.
        static let upperMarkers = [(20, 150), (235, 150), (128, 100)]
        static let lowerMarkers = [(20, 20), (235, 171), (128, 96)]

        /// The colour of pixel (`x`, `y`) of the whole frame.
        static func color(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let isLower = y >= 192
            let row = isLower ? y - 192 : y
            if x == 0 || x == width - 1 || row == 0 || row == 191 {
                return frameColor
            }
            let markers = isLower ? lowerMarkers : upperMarkers
            if markers.contains(where: { $0 == (x, row) }) {
                return isLower ? lowerMarkerColor : upperMarkerColor
            }
            return isLower ? lowerColor : upperColor
        }
    }

    /// A mailbox holding the DS test pattern, due at once.
    static func mailboxWithDSTestPattern() -> FrameMailbox {
        let geometry = VideoGeometry(baseWidth: DSPattern.width, baseHeight: DSPattern.height,
                                     maxWidth: DSPattern.width, maxHeight: DSPattern.height, aspectRatio: 2.0 / 3.0)
        let mailbox = FrameMailbox(geometry: geometry, format: .xrgb8888)
        var bytes = [UInt8](repeating: 0, count: DSPattern.width * DSPattern.height * 4)
        for y in 0..<DSPattern.height {
            for x in 0..<DSPattern.width {
                let (red, green, blue) = DSPattern.color(x: x, y: y)
                let offset = (y * DSPattern.width + x) * 4
                // XRGB8888 in memory: blue, green, red, unused.
                bytes[offset] = blue
                bytes[offset + 1] = green
                bytes[offset + 2] = red
            }
        }
        mailbox.submit(pixels: bytes.span.bytes, width: DSPattern.width, height: DSPattern.height,
                       bytesPerRow: DSPattern.width * 4, format: .xrgb8888, stamp: FrameStamp(sequence: 1, nominalTime: 0))
        return mailbox
    }
}

#Preview("GBA, closed") {
    @Previewable @State var stats = PresentationStats()
    let geometry = FoldGeometry(container: PixelSize(width: 1398, height: 2034), safeArea: PixelInsets(top: 246, bottom: 102))
    GameStage(
        system: .gba, geometry: geometry,
        layout: GameLayout(system: .gba, geometry: geometry, showsTouchControls: true),
        mailbox: PreviewContent.mailboxWithTestPattern(), stats: stats, isPaused: false, showsControls: true,
        onButtons: { _ in }, onPointer: { _ in }, onPause: {}
    )
    .background(.black)
}

#Preview("DS, closed") {
    @Previewable @State var stats = PresentationStats()
    let geometry = FoldGeometry(container: PixelSize(width: 1398, height: 2034), safeArea: PixelInsets(bottom: 102, right: 252))
    GameStage(
        system: .ds, geometry: geometry,
        layout: GameLayout(system: .ds, geometry: geometry, showsTouchControls: true),
        mailbox: PreviewContent.mailboxWithDSTestPattern(), stats: stats, isPaused: false, showsControls: true,
        onButtons: { _ in }, onPointer: { _ in }, onPause: {}
    )
    .background(.black)
}
#endif
