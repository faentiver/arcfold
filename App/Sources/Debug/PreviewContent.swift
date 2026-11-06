#if DEBUG
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
}

#Preview("Game screen") {
    @Previewable @State var stats = PresentationStats()
    VStack(spacing: 0) {
        GameScreen(mailbox: PreviewContent.mailboxWithTestPattern(), stats: stats)
            .aspectRatio(1.5, contentMode: .fit)
        TouchControls(isLandscape: false) { _ in }
    }
    .background(.black)
    .overlay(alignment: .topLeading) {
        Text(verbatim: "\(PreviewContent.systemInfo.libraryName) \(PreviewContent.systemInfo.libraryVersion)")
            .font(.caption.monospaced())
            .foregroundStyle(.white)
            .padding(8)
    }
}
#endif
