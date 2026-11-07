import Darwin
import GameController
import Metal
import QuartzCore
import Synchronization
import SwiftUI
import UIKit

/// The picture of a running game: the newest due frame of a `FrameMailbox`,
/// at the largest whole-number scale that fits, centred, black around it.
///
/// Drawn with Metal into a `CAMetalLayer`, paced by a `CAMetalDisplayLink` on
/// the main run loop. The main thread never waits for the emulation or the GPU.
public struct GameScreen: UIViewRepresentable {
    private let mailbox: FrameMailbox
    private let stats: PresentationStats
    private let isPaused: Bool

    /// - Parameters:
    ///   - mailbox: The frames to show.
    ///   - stats: Where the screen counts what it presented.
    ///   - isPaused: Stops the display link and keeps the last picture.
    public init(mailbox: FrameMailbox, stats: PresentationStats, isPaused: Bool = false) {
        self.mailbox = mailbox
        self.stats = stats
        self.isPaused = isPaused
    }

    public func makeUIView(context: Context) -> UIView {
        let view = GameScreenView(mailbox: mailbox, stats: stats)
        view.isPaused = isPaused
        return view
    }

    public func updateUIView(_ view: UIView, context: Context) {
        guard let view = view as? GameScreenView else { return }
        view.mailbox = mailbox
        view.isPaused = isPaused
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

    /// Reserve on top of the display link's lead for the run time of a frame
    /// and the wake-up delay of the emulation thread (ADR 0005, section 5).
    private static let selectionReserve = 0.008

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
            startDisplayLink()
            setNeedsLayout()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Native pixels, so that whole-number scaling stays sharp on screens
        // whose point scale differs from their panel.
        let scale = window?.windowScene?.screen.nativeScale ?? traitCollection.displayScale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard size.width > 0, size.height > 0 else { return }
        metalLayer.contentsScale = scale
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
            needsRedraw = true
            updateLinkState()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil, renderer != nil else { return }
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        link.delegate = self
        // 59.73 Hz content: at 120 Hz a frame stays one tick longer about every
        // 1.84 s for 8.3 ms, at 60 Hz every 3.67 s for 16.7 ms (ADR 0005).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.preferredFrameLatency = 1
        link.add(to: .main, forMode: .common)
        displayLink = link
        updateLinkState()
    }

    /// Paused, the link stops and the last picture stays; a size change still
    /// gets one update to draw it again.
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
        renderer.encode(into: commandBuffer, target: drawable.texture, picture: picture.upload.texture,
                        format: mailbox.format, width: picture.width, height: picture.height)
        let inFlight = picture.upload.inFlight
        inFlight.begin()
        commandBuffer.addCompletedHandler { _ in
            inFlight.end()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
