import FoldLayout
import Foundation
import LibretroKit
import Renderer
import SwiftUI

/// One reading of everything the debug overlay shows (ADR 0005, section 9).
/// Snapshots only: reading never blocks the emulation or the audio thread.
nonisolated struct DebugReadings: Sendable {
    var emulation: SessionStats.Snapshot?
    var presentation: PresentationStats.Snapshot
    var mailbox: MailboxCounters?
    var audio: AudioCounters
    /// The core's sample rate, to turn frames into milliseconds.
    var audioSampleRate: Double
    var route: AudioRoute?
    /// The buttons as the session's `InputState` sees them; nil before the
    /// session exists.
    var input: InputReadings?
    /// The pointer of the touch screen; nil for systems without one.
    var pointer: PointerReadings?
    var thermalState: ProcessInfo.ThermalState
    var isLowPowerModeEnabled: Bool
    /// Pose, geometry and layout of the game view, set by the view.
    var fold: FoldReadings? = nil
    /// The game is paused for any reason (ADR 0005, section 9; ADR 0006, section 10).
    var isPaused = false
    /// How often the game was paused since it started, however short.
    var pauses = 0

    /// The overlay's lines; also the line the app logs every 10 seconds.
    var lines: [String] {
        var lines = [emulationLine, displayLine, audioLine, inputLine]
        if let pointer {
            lines.append(pointer.line)
        }
        if let fold {
            lines += fold.lines
        }
        lines.append(deviceLine)
        return lines
    }

    /// The same values for UI tests, as `key=value` pairs joined by ";": the
    /// accessibility value of the overlay (ADR 0006, section 14).
    var accessibilityValue: String {
        var pairs: [String] = []
        if let emulation {
            pairs.append("frames=\(emulation.framesEmulated)")
            pairs.append("resyncs=\(emulation.resyncs)")
        }
        pairs.append("underruns=\(audio.underruns)")
        pairs.append("dropped=\(audio.droppedFrames)")
        pairs.append("primes=\(audio.primes)")
        pairs.append("paused=\(isPaused)")
        pairs.append("pauses=\(pauses)")
        if let input {
            pairs.append("buttonPresses=\(input.presses)")
            pairs.append("lastButtons=\(Self.names(of: input.lastPressed))")
        }
        if let pointer {
            pairs += pointer.pairs
        }
        if let fold {
            pairs += fold.pairs
        }
        return pairs.joined(separator: ";")
    }

    var emulationLine: String {
        guard let emulation else { return "Emulation –" }
        return "Emulation \(Self.number(emulation.framesPerSecond, digits: 2)) fps"
            + " · run \(Self.milliseconds(emulation.lastRunTime)) ms (max \(Self.milliseconds(emulation.maxRunTime)))"
            + " · trim \(Self.number(emulation.periodTrim * 100, digits: 3)) %"
            + " · late \(emulation.lateFrames) · resync \(emulation.resyncs)"
            + " · pauses \(pauses)" + (isPaused ? " · paused" : "")
    }

    var displayLine: String {
        var line = "Display \(Self.number(presentation.refreshRate, digits: 0)) Hz"
            + " · shown \(presentation.framesShown) · repeated \(presentation.framesRepeated)"
            + " · skipped \(presentation.framesSkipped) · late \(presentation.lateSelections)"
            + " · GPU busy \(presentation.gpuBusy)"
        if let mailbox {
            line += " · overwritten \(mailbox.overwritten)"
        }
        return line
    }

    var audioLine: String {
        let perMillisecond = audioSampleRate / 1000
        let buffered = perMillisecond > 0 ? Double(audio.bufferedFrames) / perMillisecond : 0
        let target = perMillisecond > 0 ? Double(audio.targetFrames) / perMillisecond : 0
        var line = "Audio \(Self.number(buffered, digits: 1)) ms (target \(Self.number(target, digits: 1)))"
            + " · underruns \(audio.underruns) · dropped \(audio.droppedFrames) · primes \(audio.primes)"
        if let route {
            line += " · IO \(Self.number(route.ioBufferDuration * 1000, digits: 1)) ms"
                + " · \(Self.number(route.hardwareSampleRate, digits: 0)) Hz"
        }
        return line
    }

    /// Held now, the latest press and all presses so far. The press count keeps
    /// what a short touch did; the UI test of the touch controls reads it.
    var inputLine: String {
        guard let input else { return "Input –" }
        return "Input held \(Self.names(of: input.held)) · last \(Self.names(of: input.lastPressed))"
            + " · presses \(input.presses)"
    }

    var deviceLine: String {
        "Thermal \(Self.name(of: thermalState)) · Low Power \(isLowPowerModeEnabled ? "on" : "off")"
    }

    /// RetroPad names in the order of the mask's bits, joined by "+"; "–" for none.
    static func names(of buttons: JoypadButtons) -> String {
        let all: [(button: JoypadButtons, name: String)] = [
            (.b, "B"), (.y, "Y"), (.select, "Select"), (.start, "Start"),
            (.up, "Up"), (.down, "Down"), (.left, "Left"), (.right, "Right"),
            (.a, "A"), (.x, "X"), (.l, "L"), (.r, "R"),
            (.l2, "L2"), (.r2, "R2"), (.l3, "L3"), (.r3, "R3"),
        ]
        let names = all.filter { buttons.contains($0.button) }.map(\.name)
        return names.isEmpty ? "–" : names.joined(separator: "+")
    }

    private static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return number(Double(seconds) * 1000 + Double(attoseconds) / 1e15, digits: 2)
    }

    private static func name(of state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// The input part of `DebugReadings`.
nonisolated struct InputReadings: Sendable {
    var held: JoypadButtons
    var lastPressed: JoypadButtons
    var presses: UInt64

    init(held: JoypadButtons, lastPressed: JoypadButtons, presses: UInt64) {
        self.held = held
        self.lastPressed = lastPressed
        self.presses = presses
    }

    init(_ input: InputState) {
        self.init(held: input.heldButtons, lastPressed: input.lastPressedButtons, presses: input.pressCount)
    }
}

/// The pointer of the touch screen as the session's `InputState` sees it, in
/// pixels of the core's frame and of the touch screen (ADR 0006, section 6).
nonisolated struct PointerReadings: Sendable {
    /// Where the pointer is pressed right now.
    var held: PointerPosition?
    /// Where the latest press began, kept after its release.
    var lastPress: PointerPosition?
    /// Presses since the session began; keeps what a short tap did.
    var presses: UInt64
    /// The core's frame, the extent of pointer coordinates.
    var frameSize: PixelSize
    /// The touch screen in that frame.
    var touchScreen: PixelRect

    init(held: PointerPosition?, lastPress: PointerPosition?, presses: UInt64, frameSize: PixelSize, touchScreen: PixelRect) {
        self.held = held
        self.lastPress = lastPress
        self.presses = presses
        self.frameSize = frameSize
        self.touchScreen = touchScreen
    }

    init(_ input: InputState, frameSize: PixelSize, touchScreen: PixelRect) {
        self.init(held: input.pointer, lastPress: input.lastPointerPress, presses: input.pointerPressCount,
                  frameSize: frameSize, touchScreen: touchScreen)
    }

    /// The frame pixel a pointer position aims at, the way melonDS DS reads
    /// it back: `p · W / 65534 + W / 2`, rounded down.
    static func framePixel(of position: PointerPosition, frameSize: PixelSize) -> (x: Int, y: Int) {
        func pixel(_ coordinate: Int16, _ extent: Int) -> Int {
            Int(((Double(coordinate) + 32_767) * Double(extent) / 65_534).rounded(.down))
        }
        return (pixel(position.x, frameSize.width), pixel(position.y, frameSize.height))
    }

    /// "x,y" on the touch screen, "–" for none.
    private func text(_ position: PointerPosition?) -> String {
        guard let position else { return "–" }
        let frame = Self.framePixel(of: position, frameSize: frameSize)
        return "\(frame.x - touchScreen.x),\(frame.y - touchScreen.y)"
    }

    var line: String {
        let frame = lastPress.map { Self.framePixel(of: $0, frameSize: frameSize) }
        return "Touch last \(text(lastPress))" + (frame.map { " (frame \($0.x),\($0.y))" } ?? "")
            + " · presses \(presses) · held \(text(held))"
    }

    var pairs: [String] {
        ["pointer=\(text(lastPress))", "pointerPresses=\(presses)", "pointerHeld=\(text(held))"]
    }
}

/// Pose, geometry and layout of the game view, for the overlay, the log and UI tests.
nonisolated struct FoldReadings: Sendable, Hashable {
    var geometry: FoldGeometry
    var layout: GameLayout
    /// The geometry was replaced by `-ArcfoldFoldOverride`.
    var isOverridden: Bool

    var lines: [String] {
        let fold = geometry.fold.map { "\($0) \(geometry.isFoldActive ? "active" : "inactive")" } ?? "–"
        let occlusions = geometry.occlusions.isEmpty ? "–" : geometry.occlusions.map(\.description).joined(separator: " ")
        let screens = layout.screens.map { "\($0.scale)× \($0.destination)" }.joined(separator: " · ")
        return [
            "Fold \(layout.posture.rawValue)\(isOverridden ? " (override)" : "") · view \(geometry.container) px"
                + " · safe \(geometry.safeArea) · fold \(fold) · occlusion \(occlusions)",
            "Screens \(screens)" + (layout.touchScreenIndex.map { " · touch #\($0)" } ?? ""),
        ]
    }

    var pairs: [String] {
        func rect(_ rect: PixelRect) -> String { "\(rect.x),\(rect.y),\(rect.width),\(rect.height)" }
        let insets = geometry.safeArea
        return [
            "posture=\(layout.posture.rawValue)",
            "override=\(isOverridden)",
            "scale=\(geometry.scale)",
            "view=\(geometry.container.width),\(geometry.container.height)",
            "safe=\(insets.top),\(insets.left),\(insets.bottom),\(insets.right)",
            "fold=" + (geometry.fold.map { rect($0) + (geometry.isFoldActive ? ",active" : ",inactive") } ?? "none"),
            "occlusions=" + (geometry.occlusions.isEmpty ? "none" : geometry.occlusions.map(rect).joined(separator: "|")),
            "screens=" + layout.screens.map { rect($0.destination) + ",\($0.scale)" }.joined(separator: "|"),
            "touch=" + (layout.touchScreenIndex.map(String.init) ?? "none"),
            "controls=" + (layout.controls.map { zones in
                zones.all.map(rect).joined(separator: "|") } ?? "none"),
        ]
    }
}

/// Measurements over the picture, refreshed four times a second. Technical
/// text for development and acceptance runs, so it is not localized.
struct DebugOverlay: View {
    /// Called on every refresh; must only read snapshots.
    let read: () -> DebugReadings

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The sizes of the type, largest first: the card takes the first one
    /// at which its lines fit the height on offer.
    nonisolated static let fontSizes: [CGFloat] = [10, 9, 8, 7, 6]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let readings = read()
            // Where the area on offer is low, as between the shoulder buttons
            // above the touch screen of the DS sideways, a smaller type
            // keeps every line in it.
            ViewThatFits(in: .vertical) {
                card(readings, fontSize: Self.fontSizes[0])
                card(readings, fontSize: Self.fontSizes[1])
                card(readings, fontSize: Self.fontSizes[2])
                card(readings, fontSize: Self.fontSizes[3])
                card(readings, fontSize: Self.fontSizes[4])
            }
        }
        .allowsHitTesting(false)
    }

    private func card(_ readings: DebugReadings, fontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(readings.lines, id: \.self) { line in
                Text(verbatim: line)
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .foregroundStyle(.white)
        .padding(6)
        // A measuring tool over the picture: a plain card, no glass, so it
        // costs the compositor nothing extra while it measures.
        .background(.black.opacity(contrast == .increased || reduceTransparency ? 0.85 : 0.6),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: readings.accessibilityValue))
        .accessibilityIdentifier("debug-overlay")
    }

    /// The height the card needs for `lines` in `width` at `fontSize`, with
    /// every line wrapped at words: an estimate for the tests of
    /// `OverlayPlacement`, a little above what SwiftUI lays out.
    nonisolated static func estimatedHeight(of lines: [String], width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let columns = max(1, Int(((width - 12) / (fontSize * 0.602)).rounded(.down)))
        var rows = 0
        for line in lines {
            var column = 0
            rows += 1
            for word in line.split(separator: " ") {
                if column > 0, column + 1 + word.count > columns {
                    rows += 1
                    column = 0
                }
                column += (column > 0 ? 1 : 0) + word.count
                // A word longer than a row breaks inside.
                rows += (column - 1) / columns
                column = (column - 1) % columns + 1
            }
        }
        return CGFloat(rows) * (fontSize * 1.2).rounded() + CGFloat(lines.count - 1) * 2 + 12
    }

    /// On in debug builds, off in release builds; the game menu switches it.
    static var isOnByDefault: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

#Preview {
    DebugOverlay {
        DebugReadings(
            emulation: SessionStats.Snapshot(
                framesEmulated: 3584, framesPerSecond: 59.73, lateFrames: 0, resyncs: 0,
                lastRunTime: .microseconds(420), maxRunTime: .microseconds(1100),
                maxLateness: .microseconds(800), periodTrim: -0.00012),
            presentation: PresentationStats.Snapshot(
                displayUpdates: 7200, refreshRate: 120, framesShown: 3583, framesRepeated: 3617,
                framesSkipped: 0, lateSelections: 0, gpuBusy: 0),
            mailbox: MailboxCounters(published: 3584, overwritten: 0),
            audio: AudioCounters(
                underruns: 0, underrunFrames: 0, droppedFrames: 0, primes: 1, renderCalls: 12_000,
                largestRequest: 164, bufferedFrames: 1130, targetFrames: 1147),
            audioSampleRate: 32768,
            route: AudioRoute(hardwareSampleRate: 48000, ioBufferDuration: 0.0053, outputLatency: 0.012),
            input: InputReadings(held: [.a, .right], lastPressed: .a, presses: 12),
            pointer: PointerReadings(
                held: nil, lastPress: PointerPosition(pixelX: 128, pixelY: 288, frameWidth: 256, frameHeight: 384),
                presses: 3, frameSize: SystemScreens.ds.frameSize, touchScreen: SystemScreens.ds.sources[1]),
            thermalState: .nominal,
            isLowPowerModeEnabled: false,
            fold: FoldReadings(
                geometry: FoldGeometry(container: PixelSize(width: 1398, height: 2034),
                                       safeArea: PixelInsets(bottom: 102, right: 252)),
                layout: GameLayout(system: .ds, geometry: FoldGeometry(container: PixelSize(width: 1398, height: 2034),
                                                                       safeArea: PixelInsets(bottom: 102, right: 252)),
                                   showsTouchControls: true),
                isOverridden: false)
        )
    }
    .padding()
    .background(.gray)
}
