import notify
import XCTest

/// A test program from this UI test bundle, by path. The Simulator lets the
/// app read it, which is what the debug launch arguments need.
func fixturePath(_ name: String, _ fileExtension: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
    final class Marker {}
    let url = try XCTUnwrap(Bundle(for: Marker.self).url(forResource: name, withExtension: fileExtension),
                            "\(name).\(fileExtension) is not in the UI test bundle; check project.yml", file: file, line: line)
    return url.path(percentEncoded: false)
}

/// A screenshot that could not be drawn into a bitmap.
struct UnreadableScreenshot: Error {}

/// RGBA bytes of a screenshot, in sRGB.
struct Pixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw UnreadableScreenshot() }
        self.bytes = bytes
    }

    /// The smallest rectangle around every pixel brighter than dark grey in `area`.
    func boundsOfLight(in area: (left: Int, top: Int, right: Int, bottom: Int))
        -> (left: Int, top: Int, right: Int, bottom: Int)?
    {
        var result: (left: Int, top: Int, right: Int, bottom: Int)?
        for y in max(area.top, 0)...min(area.bottom, height - 1) {
            for x in max(area.left, 0)...min(area.right, width - 1) {
                let pixel = rgb(x: x, y: y)
                guard pixel.red > 40 || pixel.green > 40 || pixel.blue > 40 else { continue }
                if let current = result {
                    result = (min(current.left, x), min(current.top, y), max(current.right, x), max(current.bottom, y))
                } else {
                    result = (x, y, x, y)
                }
            }
        }
        return result
    }

    func rgb(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let x = min(max(x, 0), width - 1)
        let y = min(max(y, 0), height - 1)
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    /// Whether pixel (`x`, `y`) has `color`, each channel within `tolerance`.
    func matches(x: Int, y: Int, _ color: (UInt8, UInt8, UInt8), tolerance: Int = 24) -> Bool {
        let pixel = rgb(x: x, y: y)
        return abs(Int(pixel.red) - Int(color.0)) <= tolerance
            && abs(Int(pixel.green) - Int(color.1)) <= tolerance
            && abs(Int(pixel.blue) - Int(color.2)) <= tolerance
    }

    func describe(x: Int, y: Int) -> String {
        let pixel = rgb(x: x, y: y)
        return "(\(pixel.red), \(pixel.green), \(pixel.blue)) at (\(x), \(y))"
    }
}

/// A rectangle in view pixels with the scale of a placed screen.
struct PlacedRect: Equatable, CustomStringConvertible {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var scale: Int

    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var description: String { "\(scale)× (\(x), \(y), \(width)×\(height))" }

    func contains(x px: Int, y py: Int) -> Bool {
        px >= x && px < maxX && py >= y && py < maxY
    }
}

/// The accessibility value of the debug overlay: `key=value` pairs joined by
/// ";" (DebugReadings.accessibilityValue in the app).
struct OverlayValues {
    let pairs: [String: String]

    @MainActor
    init(_ element: XCUIElement) {
        let text = element.value as? String ?? ""
        var pairs: [String: String] = [:]
        for pair in text.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                pairs[String(parts[0])] = String(parts[1])
            }
        }
        self.pairs = pairs
    }

    subscript(key: String) -> String? { pairs[key] }

    private func numbers(_ key: String) -> [Int] {
        (pairs[key] ?? "").split(separator: ",").compactMap { Int($0) }
    }

    var posture: String? { pairs["posture"] }
    var scale: Int { numbers("scale").first ?? 3 }
    var view: (width: Int, height: Int)? {
        let values = numbers("view")
        return values.count == 2 ? (values[0], values[1]) : nil
    }

    /// Top, left, bottom, right.
    var safe: (top: Int, left: Int, bottom: Int, right: Int)? {
        let values = numbers("safe")
        return values.count == 4 ? (values[0], values[1], values[2], values[3]) : nil
    }

    var screens: [PlacedRect] {
        (pairs["screens"] ?? "").split(separator: "|").compactMap { item in
            let values = item.split(separator: ",").compactMap { Int($0) }
            return values.count == 5 ? PlacedRect(x: values[0], y: values[1], width: values[2], height: values[3], scale: values[4]) : nil
        }
    }

    var touchScreen: PlacedRect? {
        guard let index = pairs["touch"].flatMap({ Int($0) }), screens.indices.contains(index) else { return nil }
        return screens[index]
    }

    var pointerPresses: Int? { pairs["pointerPresses"].flatMap { Int($0) } }
    var buttonPresses: Int? { pairs["buttonPresses"].flatMap { Int($0) } }

    /// Frames the emulation ran, its resynchronisations, the sound's
    /// underruns, dropped frames and primings, and whether the game is paused.
    var frames: Int? { pairs["frames"].flatMap { Int($0) } }
    var resyncs: Int? { pairs["resyncs"].flatMap { Int($0) } }
    var underruns: Int? { pairs["underruns"].flatMap { Int($0) } }
    var dropped: Int? { pairs["dropped"].flatMap { Int($0) } }
    var primes: Int? { pairs["primes"].flatMap { Int($0) } }
    var isPaused: Bool? { pairs["paused"].map { $0 == "true" } }
    /// How often the game was paused since it started, however short.
    var pauses: Int? { pairs["pauses"].flatMap { Int($0) } }
}

/// Posts a Darwin notification for `DebugRemote` in the debug build of the
/// app, for example "fold.tabletop", "hinge.closed" or "overlay.hide" (ADR
/// 0006, section 15). The UI test runner and the app share the Simulator's
/// notification centre.
func postDebugNotification(_ name: String) {
    _ = notify_post("com.faentiver.arcfold.debug." + name)
}

/// A row of 8 × 8 blocks in which a selftest program shows a number (see the
/// generators under Tests/Fixtures): bit i at source x = 8 + (bits − 1 − i) ·
/// spacing, source y = row, the most significant bit on the left.
struct BlockRow: CustomStringConvertible {
    var name: String
    var row: Int
    var bits: Int
    var spacing: Int

    /// selftest.nds, upper screen: frames of the ARM9 (frame number − 7 in
    /// melonDS DS) and of the ARM7 (frame number − 1).
    static let dsARM9Frames = BlockRow(name: "ARM9 frames", row: 8, bits: 24, spacing: 10)
    static let dsARM7Frames = BlockRow(name: "ARM7 frames", row: 116, bits: 16, spacing: 10)
    /// selftest.gba: frames since the first vertical blank (frame number − 6 in mGBA).
    static let gbaFrames = BlockRow(name: "frames", row: 128, bits: 16, spacing: 14)

    var description: String { name }

    /// The number on `screen` in a screenshot, read in the middle of each
    /// block. An unlit block has the grey of BGR555 0x18C6 (48 or 49 in each
    /// channel), a lit one a brighter colour. Nil when a block lies under
    /// something in `covered` or is neither.
    func value(in pixels: Pixels, on screen: PlacedRect, covered: [CGRect]) -> Int? {
        var value = 0
        for bit in 0..<bits {
            let sourceX = 8 + (bits - 1 - bit) * spacing + 4
            let x = screen.x + sourceX * screen.scale
            let y = screen.y + (row + 4) * screen.scale
            guard x < pixels.width, y < pixels.height,
                  !covered.contains(where: { $0.contains(CGPoint(x: x, y: y)) })
            else { return nil }
            let pixel = pixels.rgb(x: x, y: y)
            let channels = [Int(pixel.red), Int(pixel.green), Int(pixel.blue)]
            if channels.allSatisfy({ abs($0 - 49) <= 20 }) {
                continue
            }
            guard channels.max() ?? 0 > 100 else { return nil }
            value |= 1 << bit
        }
        return value
    }
}

extension XCUIApplication {
    /// The app's window. Taps at view coordinates and screenshots of the game
    /// go through it, because on the inner display of the Duo Simulator
    /// (iOS 27.1) the application element keeps the frame of the display's
    /// native orientation (669 × 951 pt while the window is 951 × 669 pt): a
    /// tap relative to the application then misses the window, and
    /// `XCUIScreen.main` stays the outer display, which is off. The window has
    /// the frame of the view on the display that shows it
    /// (docs/wissen/falz.md, section Stolperfallen).
    var gameWindow: XCUIElement { windows.firstMatch }

    /// The top left corner of the game view, for taps at view coordinates.
    var viewOrigin: XCUICoordinate { gameWindow.coordinate(withNormalizedOffset: .zero) }

    /// A screenshot of the display that shows the app. Pixel checks read it
    /// through `uprightImage`, which puts it into view pixels.
    func displayScreenshot() -> XCUIScreenshot { gameWindow.screenshot() }
}

extension XCUIScreenshot {
    /// The pixels as the view shows them, view pixel (x, y) at (x, y).
    ///
    /// On the inner display of the Duo Simulator (iOS 27.1) XCTest leaves off
    /// the last row and the last column of the bitmap in the display's own
    /// orientation (2006 × 2852 instead of 2007 × 2853 px). While the Duo is
    /// held upright and open (open, book), the display lies on its side: the
    /// bitmap comes with the orientation `.right`, and drawn upright the
    /// missing row is the view's first column, so every pixel sits one to the
    /// left. Measured on 7 November 2026 against `simctl io screenshot`: drawn
    /// upright and moved one pixel to the right, the two agree (mean
    /// difference 0.03 per pixel). With `.up` (tabletop, flat upright, the
    /// outer display) the missing row and column lie at the right and bottom
    /// edges and nothing moves. `.left` and `.down` follow from the same rule
    /// and are not measured.
    var uprightImage: CGImage? {
        let image = self.image
        let shift: (x: CGFloat, y: CGFloat)
        switch image.imageOrientation {
        case .up: return image.cgImage
        case .right: shift = (1, 0)
        case .left: shift = (0, 1)
        case .down: shift = (1, 1)
        default: shift = (0, 0)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.preferredRange = .standard
        let pixel = 1 / image.scale
        let size = CGSize(width: image.size.width + pixel, height: image.size.height + pixel)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(x: shift.x * pixel, y: shift.y * pixel, width: image.size.width, height: image.size.height))
        }.cgImage
    }
}

extension XCTestCase {
    /// The debug overlay, once it shows the layout.
    @MainActor
    func overlayWithLayout(in app: XCUIApplication, timeout: TimeInterval = 30) -> XCUIElement {
        let overlay = app.descendants(matching: .any)["debug-overlay"].firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: timeout), "No debug overlay")
        let hasLayout = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "screens="), object: overlay)
        XCTAssertEqual(XCTWaiter().wait(for: [hasLayout], timeout: timeout), .completed, "The overlay shows no layout")
        return overlay
    }

    /// Waits until the overlay's value contains `text`.
    @MainActor
    @discardableResult
    func waitUntil(_ overlay: XCUIElement, hasValue text: String, timeout: TimeInterval = 10) -> Bool {
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: overlay)
        return XCTWaiter().wait(for: [shows], timeout: timeout) == .completed
    }

    /// Keeps a screenshot in the result bundle as evidence of the run.
    @MainActor
    func keep(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The frames, in view pixels, of what lies over the screens: the debug
    /// overlay (unless left out), the touch controls and the pause button.
    /// Pixel checks skip them.
    @MainActor
    func coveredRects(in app: XCUIApplication, scale: Int, includingOverlay: Bool = true) -> [CGRect] {
        var frames: [CGRect] = []
        if includingOverlay {
            let overlay = app.descendants(matching: .any)["debug-overlay"].firstMatch
            if overlay.exists {
                frames.append(overlay.frame)
            }
        }
        let controls = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ OR identifier == %@ OR identifier == %@", "touch-button-", "touch-pad", "pause"))
        for index in 0..<controls.count {
            frames.append(controls.element(boundBy: index).frame)
        }
        let s = CGFloat(scale)
        return frames.filter { !$0.isEmpty }.map {
            CGRect(x: $0.minX * s, y: $0.minY * s, width: $0.width * s, height: $0.height * s).insetBy(dx: -3, dy: -3)
        }
    }

    /// The debug overlay's frame in view pixels, with the margin of
    /// `coveredRects`; nil while it is hidden.
    @MainActor
    func overlayRect(in app: XCUIApplication, scale: Int) -> CGRect? {
        let overlay = app.descendants(matching: .any)["debug-overlay"].firstMatch
        guard overlay.exists, !overlay.frame.isEmpty else { return nil }
        let s = CGFloat(scale)
        let frame = overlay.frame
        return CGRect(x: frame.minX * s, y: frame.minY * s, width: frame.width * s, height: frame.height * s).insetBy(dx: -3, dy: -3)
    }

    /// Runs `body` with the debug overlay hidden (`DebugRemote` in the app),
    /// for a screenshot of the whole picture, and brings the overlay back.
    @MainActor
    func withOverlayHidden<T>(in app: XCUIApplication, _ body: () throws -> T) rethrows -> T {
        let overlay = app.descendants(matching: .any)["debug-overlay"].firstMatch
        postDebugNotification("overlay.hide")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: overlay)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "The overlay did not hide")
        defer {
            postDebugNotification("overlay.show")
            XCTAssertTrue(overlay.waitForExistence(timeout: 5), "The overlay did not come back")
        }
        return try body()
    }
}
