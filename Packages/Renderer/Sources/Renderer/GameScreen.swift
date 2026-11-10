import Darwin
import GameController
import Metal
import os
import QuartzCore
import Synchronization
import SwiftUI
import UIKit

/// The picture of a running game: the newest due frame of a `FrameMailbox`.
/// Without an arrangement the whole frame sits at the largest whole-number
/// scale that fits, centred; with one, each viewport shows its part of the
/// frame (ADR 0006). Black around it.
///
/// Drawn with Metal into a `CAMetalLayer`, paced by a `CAMetalDisplayLink` on
/// the main run loop. The main thread never waits for the emulation or the GPU.
public struct GameScreen: UIViewRepresentable {
    private let mailbox: FrameMailbox
    private let stats: PresentationStats
    private let isPaused: Bool
    private let arrangement: ScreenArrangement?

    /// - Parameters:
    ///   - mailbox: The frames to show.
    ///   - stats: Where the screen counts what it presented.
    ///   - isPaused: Stops the display link and keeps the last picture.
    ///   - arrangement: Where the screens of each frame go, from FoldLayout;
    ///     nil fits the whole frame.
    public init(mailbox: FrameMailbox, stats: PresentationStats, isPaused: Bool = false,
                arrangement: ScreenArrangement? = nil) {
        self.mailbox = mailbox
        self.stats = stats
        self.isPaused = isPaused
        self.arrangement = arrangement
    }

    public func makeUIView(context: Context) -> UIView {
        let view = GameScreenView(mailbox: mailbox, stats: stats)
        view.isPaused = isPaused
        view.arrangement = arrangement
        return view
    }

    public func updateUIView(_ view: UIView, context: Context) {
        guard let view = view as? GameScreenView else { return }
        view.mailbox = mailbox
        view.isPaused = isPaused
        view.arrangement = arrangement
    }
}

/// What the screen presented, for the debug overlay. Written on the main
/// thread by `GameScreen`, readable from anywhere.
public final class PresentationStats: Sendable {
    /// One reading of all values.
    public struct Snapshot: Sendable, Hashable {
        /// Display link callbacks since the screen appeared.
        public var displayUpdates: UInt64
        /// The refresh rate the display link runs at, in Hz.
        public var refreshRate: Double
        /// Frames shown for the first time.
        public var framesShown: UInt64
        /// Display updates that kept the previous frame because no new one was due.
        public var framesRepeated: UInt64
        /// Delivered frames that were never shown.
        public var framesSkipped: UInt64
        /// Updates where the due frame was not ready yet and an older one was shown.
        public var lateSelections: UInt64
        /// Updates skipped because the GPU still used the next texture.
        public var gpuBusy: UInt64

        public init(
            displayUpdates: UInt64, refreshRate: Double, framesShown: UInt64, framesRepeated: UInt64,
            framesSkipped: UInt64, lateSelections: UInt64, gpuBusy: UInt64
        ) {
            self.displayUpdates = displayUpdates
            self.refreshRate = refreshRate
            self.framesShown = framesShown
            self.framesRepeated = framesRepeated
            self.framesSkipped = framesSkipped
            self.lateSelections = lateSelections
            self.gpuBusy = gpuBusy
        }
    }

    private let displayUpdates = Atomic<UInt64>(0)
    /// The bit pattern of a Double.
    private let refreshRate = Atomic<UInt64>(0)
    private let framesShown = Atomic<UInt64>(0)
    private let framesRepeated = Atomic<UInt64>(0)
    private let framesSkipped = Atomic<UInt64>(0)
    private let lateSelections = Atomic<UInt64>(0)
    private let gpuBusy = Atomic<UInt64>(0)

    public init() {}

    /// The current values.
    public func snapshot() -> Snapshot {
        Snapshot(
            displayUpdates: displayUpdates.load(ordering: .relaxed),
            refreshRate: Double(bitPattern: refreshRate.load(ordering: .relaxed)),
            framesShown: framesShown.load(ordering: .relaxed),
            framesRepeated: framesRepeated.load(ordering: .relaxed),
            framesSkipped: framesSkipped.load(ordering: .relaxed),
            lateSelections: lateSelections.load(ordering: .relaxed),
            gpuBusy: gpuBusy.load(ordering: .relaxed)
        )
    }

    package func recordDisplayUpdate(refreshRate rate: Double) {
        displayUpdates.wrappingAdd(1, ordering: .relaxed)
        refreshRate.store(rate.bitPattern, ordering: .relaxed)
    }

    package func recordShown(skipped: Int, isLate: Bool) {
        framesShown.wrappingAdd(1, ordering: .relaxed)
        framesSkipped.wrappingAdd(UInt64(skipped), ordering: .relaxed)
        if isLate {
            lateSelections.wrappingAdd(1, ordering: .relaxed)
        }
    }

    package func recordRepeated() {
        framesRepeated.wrappingAdd(1, ordering: .relaxed)
    }

    package func recordGPUBusy() {
        gpuBusy.wrappingAdd(1, ordering: .relaxed)
    }
}

/// One of three textures the screen uploads pictures into. The GPU may still
/// read it after the frame was committed; `inFlight` counts the command buffers
/// that use it and drops back in their completion handlers.
private final class UploadTexture {
    let texture: any MTLTexture
    let inFlight = InFlightCounter()

    init(texture: any MTLTexture) {
        self.texture = texture
    }
}

/// The part of an upload texture the completion handler touches, on a Metal thread.
private final class InFlightCounter: Sendable {
    private let count = Atomic<Int>(0)

    /// Acquire: the GPU's reads of the texture happened before the next upload.
    var isBusy: Bool { count.load(ordering: .acquiring) > 0 }

    func begin() {
        count.wrappingAdd(1, ordering: .relaxed)
    }

    func end() {
        count.wrappingSubtract(1, ordering: .releasing)
    }
}

/// The UIKit view behind `GameScreen`.
final class GameScreenView: UIView, CAMetalDisplayLinkDelegate {
    override static var layerClass: AnyClass { CAMetalLayer.self }

    var mailbox: FrameMailbox {
        didSet {
            if mailbox !== oldValue {
                textures = []
                current = nil
            }
        }
    }

    var isPaused = false {
        didSet { updateLinkState() }
    }

    /// The viewports of the screens and the scale of the drawable (ADR 0006).
    /// A change draws the current picture again, also while paused.
    var arrangement: ScreenArrangement? {
        didSet {
            guard arrangement != oldValue else { return }
            if arrangement?.pixelsPerPoint != oldValue?.pixelsPerPoint {
                setNeedsLayout()
            }
            needsRedraw = true
            updateLinkState()
        }
    }

    private let stats: PresentationStats
    private let renderer: PictureRenderer?
    private var displayLink: CAMetalDisplayLink?
    private var textures: [UploadTexture] = []
    private var nextTexture = 0
    /// The picture on screen, kept for redrawing after a size change.
    private var current: (upload: UploadTexture, width: Int, height: Int)?
    private var needsRedraw = false
    /// Smoothed time from a callback to its presentation, in seconds.
    private var leadTime = 0.0
    private var lastTargetTimestamp: CFTimeInterval = 0
    private var refreshRate = 0.0
    private let hostTicksPerSecond: Double
    /// The scene and the screen the view was last seen on.
    private var sceneIdentity: ObjectIdentifier?
    private var screenTraits: ScreenTraits?

    /// Reserve on top of the display link's lead for the run time of a frame
    /// and the wake-up delay of the emulation thread (ADR 0005, section 5).
    private static let selectionReserve = 0.008

    /// Scene, screen and drawable changes, as evidence for the pose check
    /// (Scripts/pose-check.sh, ADR 0006, section 9).
    private nonisolated static let logger = Logger(subsystem: "com.faentiver.arcfold", category: "fold")

    private var metalLayer: CAMetalLayer {
        // layerClass guarantees the type.
        layer as! CAMetalLayer
    }

    init(mailbox: FrameMailbox, stats: PresentationStats) {
        self.mailbox = mailbox
        self.stats = stats
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        hostTicksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        if let device = MTLCreateSystemDefaultDevice() {
            renderer = try? PictureRenderer(device: device)
        } else {
            renderer = nil
        }
        super.init(frame: .zero)

        backgroundColor = .black
        isOpaque = true
        let layer = metalLayer
        layer.device = renderer?.device
        layer.pixelFormat = PictureRenderer.targetPixelFormat
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.isOpaque = true

        // Gamepad events go to the GameController framework, not to UIKit's
        // focus and press handling.
        let interaction = GCEventInteraction()
        interaction.handledEventTypes = .gamepad
        addInteraction(interaction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GameScreenView is created in code only")
    }

    // MARK: Layout and lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            followScene()
            startDisplayLink()
            setNeedsLayout()
        } else {
            stopDisplayLink()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        followScene()
        // With an arrangement the drawable has the pixels per point FoldLayout
        // computed with, so both mean the same pixels (ADR 0006). Without one,
        // native pixels as in M1, so that whole-number scaling stays sharp on
        // screens whose point scale differs from their panel.
        let scale = arrangement.map { CGFloat($0.pixelsPerPoint) }
            ?? window?.windowScene?.screen.nativeScale ?? traitCollection.displayScale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard size.width > 0, size.height > 0 else { return }
        metalLayer.contentsScale = scale
        if metalLayer.drawableSize != size {
            let old = metalLayer.drawableSize
            Self.logger.notice("""
                Drawable \(Int(old.width))×\(Int(old.height)) → \(Int(size.width))×\(Int(size.height)) px \
                at \(scale, format: .fixed(precision: 0)) px/pt
                """)
            metalLayer.drawableSize = size
            needsRedraw = true
            updateLinkState()
        }
    }

    /// Notes when the view moves to another scene or screen. On another
    /// screen the display link starts again with that screen's frame rates:
    /// whether a link follows its layer from the outer to the inner display
    /// is unknown, a new one does not depend on it (ADR 0006, section 9).
    private func followScene() {
        guard let scene = window?.windowScene else { return }
        let sceneID = ObjectIdentifier(scene)
        if sceneID != sceneIdentity {
            let isFirst = sceneIdentity == nil
            sceneIdentity = sceneID
            Self.logger.notice("""
                Scene \(isFirst ? "shown in" : "changed to", privacy: .public) \
                \(scene.session.persistentIdentifier, privacy: .public)
                """)
        }
        let traits = ScreenTraits(scene.screen)
        guard traits != screenTraits else { return }
        let previous = screenTraits
        screenTraits = traits
        Self.logger.notice("""
            Screen \(previous == nil ? "is" : "changed to", privacy: .public) \(traits.description, privacy: .public)
            """)
        // A new screen, or one with other frame rates; a turned screen only
        // changes its size.
        if let previous, displayLink != nil,
           previous.identity != traits.identity || previous.maximumFramesPerSecond != traits.maximumFramesPerSecond {
            stopDisplayLink()
            startDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil, renderer != nil else { return }
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        link.delegate = self
        // 59.73 Hz content: at 120 Hz a frame stays one tick longer about every
        // 1.84 s for 8.3 ms, at 60 Hz every 3.67 s for 16.7 ms (ADR 0005). The
        // range follows the screen: 60 Hz in the Simulator, up to 120 Hz on a
        // ProMotion display.
        let maximum = Float(screenTraits?.maximumFramesPerSecond ?? 120)
        let preferred = min(max(maximum, 30), 120)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, preferred), maximum: preferred, preferred: preferred)
        link.preferredFrameLatency = 1
        link.add(to: .main, forMode: .common)
        displayLink = link
        leadTime = 0
        lastTargetTimestamp = 0
        Self.logger.notice("Display link started, \(preferred, format: .fixed(precision: 0)) Hz preferred")
        updateLinkState()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Paused, the link stops and the last picture stays; a size or
    /// arrangement change still gets one update to draw it again.
    private func updateLinkState() {
        displayLink?.isPaused = isPaused && !needsRedraw
    }

    // MARK: Display link

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let now = CACurrentMediaTime()
        measure(update, now: now)
        guard let renderer else { return }

        if isPaused {
            // Only here to draw the last picture after a size change.
            if let current {
                draw(current, renderer: renderer, into: update.drawable)
            }
            needsRedraw = false
            updateLinkState()
            return
        }

        prepareTextures(renderer: renderer)
        guard !textures.isEmpty else { return }
        let upload = textures[nextTexture]
        if upload.inFlight.isBusy {
            stats.recordGPUBusy()
            redrawIfNeeded(renderer: renderer, into: update.drawable)
            return
        }

        let presentationTime = hostTime(update.targetPresentationTimestamp)
        let latency = hostTime(leadTime + Self.selectionReserve)
        switch mailbox.takeFrame(presentationTime: presentationTime, latency: latency) {
        case .none:
            stats.recordRepeated()
            redrawIfNeeded(renderer: renderer, into: update.drawable)
        case let .frame(frame, skipped, isLate):
            renderer.upload(pixels: frame.pixels, width: frame.width, height: frame.height,
                            bytesPerRow: frame.bytesPerRow, into: upload.texture)
            mailbox.release(frame)
            nextTexture = (nextTexture + 1) % textures.count
            let picture = (upload: upload, width: frame.width, height: frame.height)
            current = picture
            draw(picture, renderer: renderer, into: update.drawable)
            needsRedraw = false
            stats.recordShown(skipped: skipped, isLate: isLate)
        }
    }

    /// Smooths the lead of the link and its refresh rate.
    private func measure(_ update: CAMetalDisplayLink.Update, now: CFTimeInterval) {
        let lead = update.targetPresentationTimestamp - now
        if lead > 0, lead < 0.25 {
            leadTime = leadTime == 0 ? lead : leadTime + (lead - leadTime) * 0.1
        }
        let interval = update.targetTimestamp - lastTargetTimestamp
        lastTargetTimestamp = update.targetTimestamp
        if interval > 0.002, interval < 0.1 {
            let rate = 1 / interval
            refreshRate = refreshRate == 0 ? rate : refreshRate + (rate - refreshRate) * 0.1
        }
        stats.recordDisplayUpdate(refreshRate: refreshRate)
    }

    private func hostTime(_ seconds: CFTimeInterval) -> UInt64 {
        seconds > 0 ? UInt64(seconds * hostTicksPerSecond) : 0
    }

    private func prepareTextures(renderer: PictureRenderer) {
        guard textures.isEmpty else { return }
        for _ in 0..<3 {
            guard let texture = renderer.makeUploadTexture(
                format: mailbox.format, width: mailbox.maxWidth, height: mailbox.maxHeight)
            else {
                textures = []
                return
            }
            textures.append(UploadTexture(texture: texture))
        }
        nextTexture = 0
    }

    private func redrawIfNeeded(renderer: PictureRenderer, into drawable: any CAMetalDrawable) {
        guard needsRedraw, let current else { return }
        draw(current, renderer: renderer, into: drawable)
        needsRedraw = false
    }

    private func draw(_ picture: (upload: UploadTexture, width: Int, height: Int), renderer: PictureRenderer,
                      into drawable: any CAMetalDrawable) {
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }
        if let arrangement {
            renderer.encode(into: commandBuffer, target: drawable.texture, picture: picture.upload.texture,
                            format: mailbox.format, frameWidth: picture.width, frameHeight: picture.height,
                            viewports: arrangement.viewports)
        } else {
            renderer.encode(into: commandBuffer, target: drawable.texture, picture: picture.upload.texture,
                            format: mailbox.format, width: picture.width, height: picture.height)
        }
        let inFlight = picture.upload.inFlight
        inFlight.begin()
        commandBuffer.addCompletedHandler { _ in
            inFlight.end()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// What the display link and the log care about of a screen. Compared as a
/// whole, so that a screen object that changes its size counts as a change too.
private struct ScreenTraits: Equatable {
    let identity: ObjectIdentifier
    let size: CGSize
    let nativeScale: CGFloat
    let maximumFramesPerSecond: Int

    @MainActor
    init(_ screen: UIScreen) {
        identity = ObjectIdentifier(screen)
        size = screen.bounds.size
        nativeScale = screen.nativeScale
        maximumFramesPerSecond = screen.maximumFramesPerSecond
    }

    var description: String {
        "\(Int(size.width))×\(Int(size.height)) pt, native scale \(nativeScale), "
            + "\(maximumFramesPerSecond) Hz maximum, id \(identity.hashValue)"
    }
}
