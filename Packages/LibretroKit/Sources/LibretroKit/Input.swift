import Synchronization

/// Buttons of the libretro RetroPad. Bit n is `RETRO_DEVICE_ID_JOYPAD_*` = n,
/// so the raw value is the mask a core reads with `RETRO_DEVICE_ID_JOYPAD_MASK`.
///
/// The names follow the RetroPad: `a` is the right face button, `b` the lower
/// one. Which physical control sets which button is decided by the app.
public struct JoypadButtons: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let b = JoypadButtons(rawValue: 1 << 0)
    public static let y = JoypadButtons(rawValue: 1 << 1)
    public static let select = JoypadButtons(rawValue: 1 << 2)
    public static let start = JoypadButtons(rawValue: 1 << 3)
    public static let up = JoypadButtons(rawValue: 1 << 4)
    public static let down = JoypadButtons(rawValue: 1 << 5)
    public static let left = JoypadButtons(rawValue: 1 << 6)
    public static let right = JoypadButtons(rawValue: 1 << 7)
    public static let a = JoypadButtons(rawValue: 1 << 8)
    public static let x = JoypadButtons(rawValue: 1 << 9)
    public static let l = JoypadButtons(rawValue: 1 << 10)
    public static let r = JoypadButtons(rawValue: 1 << 11)
    public static let l2 = JoypadButtons(rawValue: 1 << 12)
    public static let r2 = JoypadButtons(rawValue: 1 << 13)
    public static let l3 = JoypadButtons(rawValue: 1 << 14)
    public static let r3 = JoypadButtons(rawValue: 1 << 15)
}

/// A position on the core's whole picture in libretro pointer coordinates
/// (`RETRO_DEVICE_POINTER`): −0x7FFF is the left or top edge of the frame and
/// 0x7FFF the right or bottom edge, whatever the frame's size (ADR 0006).
public struct PointerPosition: Sendable, Hashable {
    public var x: Int16
    public var y: Int16

    public init(x: Int16, y: Int16) {
        self.x = x
        self.y = y
    }

    /// Aims at the centre of pixel (`pixelX`, `pixelY`) of a frame of
    /// `frameWidth` × `frameHeight` pixels. The DS touch screen pixel (x, y),
    /// for example, is pixel (x, 192 + y) of melonDS's 256 × 384 frame.
    public init(pixelX: Int, pixelY: Int, frameWidth: Int, frameHeight: Int) {
        self.init(
            x: Self.coordinate(forPixel: pixelX, extent: frameWidth),
            y: Self.coordinate(forPixel: pixelY, extent: frameHeight)
        )
    }

    /// The coordinate of the centre of `pixel` in a frame `extent` pixels wide
    /// or high: round((pixel + 0.5) / extent · 65534 − 32767). melonDS DS maps
    /// it back with `p · extent / 65534 + extent / 2`, truncated, and lands on
    /// `pixel` with room to spare on both sides (ADR 0006).
    public static func coordinate(forPixel pixel: Int, extent: Int) -> Int16 {
        precondition(extent > 0 && pixel >= 0 && pixel < extent, "The pixel lies outside the frame")
        return Int16(((Double(pixel) + 0.5) / Double(extent) * 65_534 - 32_767).rounded())
    }
}

/// The buttons the core sees on port 0, combined from all input sources, and
/// the pointer of the touch screen (ADR 0006).
///
/// Every source keeps its own mask; the core sees their union. A button pressed
/// and released again between two polls still reaches the core for one frame
/// (it is latched until the next `retro_input_poll`); so does a touch of the
/// pointer. Lock-free: writers and the emulation thread only touch atomics.
public final class InputState: Sendable {
    /// Where buttons come from. Each source has exactly one writer.
    public enum Source: Int, Sendable, Hashable, CaseIterable {
        /// The touch overlay.
        case touch
        /// Game controllers (GameController framework).
        case controller
        /// A hardware keyboard, for example the Mac keyboard in the Simulator.
        case keyboard
    }

    private let touch = Atomic<UInt32>(0)
    private let controller = Atomic<UInt32>(0)
    private let keyboard = Atomic<UInt32>(0)
    /// Buttons pressed since the last poll, kept even if released again.
    private let latch = Atomic<UInt32>(0)
    /// Every button that went down, counted once per press and source.
    private let presses = Atomic<UInt64>(0)
    /// The buttons of the latest press.
    private let lastPress = Atomic<UInt32>(0)

    // The pointer, packed into one word so that a reader never sees x of one
    // touch and y of another: x in bits 0-15, y in bits 16-31 (bit patterns of
    // the Int16 values), bit 32 set while it is pressed.
    private let pointerState = Atomic<UInt64>(0)
    /// The start of a press since the last poll, packed the same way; 0 for none.
    private let pointerLatch = Atomic<UInt64>(0)
    private let pointerPresses = Atomic<UInt64>(0)
    /// The start of the latest press with bit 32 set; 0 before the first press.
    private let lastPointerPressState = Atomic<UInt64>(0)
    private static let pointerPressed: UInt64 = 1 << 32

    public init() {}

    /// Replaces the buttons held through `source`. Callable from any thread,
    /// but only from one writer per source.
    public func set(_ buttons: JoypadButtons, from source: Source) {
        let previous = switch source {
        case .touch: touch.exchange(buttons.rawValue, ordering: .relaxed)
        case .controller: controller.exchange(buttons.rawValue, ordering: .relaxed)
        case .keyboard: keyboard.exchange(buttons.rawValue, ordering: .relaxed)
        }
        let pressed = buttons.rawValue & ~previous
        if pressed != 0 {
            latch.bitwiseOr(pressed, ordering: .relaxed)
            presses.wrappingAdd(UInt64(pressed.nonzeroBitCount), ordering: .relaxed)
            lastPress.store(pressed, ordering: .relaxed)
        }
    }

    /// The union of all sources right now, without the latch. For the debug
    /// overlay and tests; the core reads its own snapshot once per frame.
    public var heldButtons: JoypadButtons {
        JoypadButtons(rawValue: held)
    }

    /// Every button that went down since the state was made, counted once per
    /// press and source. For the debug overlay: it keeps what a short touch
    /// did, which a UI test cannot watch while it presses.
    public var pressCount: UInt64 {
        presses.load(ordering: .relaxed)
    }

    /// The buttons of the latest press, kept after their release. For the
    /// debug overlay and tests.
    public var lastPressedButtons: JoypadButtons {
        JoypadButtons(rawValue: lastPress.load(ordering: .relaxed))
    }

    /// The snapshot for one frame (`retro_input_poll`): every button held now,
    /// plus every button pressed since the previous poll. Clears the latch.
    /// Emulation thread only; no locks, no allocation.
    func poll() -> UInt32 {
        held | latch.exchange(0, ordering: .relaxed)
    }

    // MARK: Pointer

    /// Presses the pointer at `position`, or lifts it with nil. A finger that
    /// moves while it is down calls this again with the new position. Callable
    /// from any thread, but only from one writer: the touch screen of the app.
    public func setPointer(_ position: PointerPosition?) {
        let previous = pointerState.load(ordering: .relaxed)
        // Lifted, the pointer keeps its last coordinates.
        let state = position.map { Self.pack($0) | Self.pointerPressed } ?? previous & ~Self.pointerPressed
        pointerState.store(state, ordering: .relaxed)
        if position != nil, previous & Self.pointerPressed == 0 {
            pointerLatch.store(state, ordering: .relaxed)
            pointerPresses.wrappingAdd(1, ordering: .relaxed)
            lastPointerPressState.store(state, ordering: .relaxed)
        }
    }

    /// Where the pointer is pressed right now; nil while it is lifted. For the
    /// debug overlay and tests; the core reads its own snapshot once per frame.
    public var pointer: PointerPosition? {
        let state = pointerState.load(ordering: .relaxed)
        return state & Self.pointerPressed != 0 ? Self.unpack(state) : nil
    }

    /// Presses of the pointer since the state was made. For the debug overlay:
    /// it keeps what a short touch did, which a UI test cannot watch while it taps.
    public var pointerPressCount: UInt64 {
        pointerPresses.load(ordering: .relaxed)
    }

    /// Where the latest press of the pointer began, kept after its release;
    /// nil before the first press.
    public var lastPointerPress: PointerPosition? {
        let state = lastPointerPressState.load(ordering: .relaxed)
        return state & Self.pointerPressed != 0 ? Self.unpack(state) : nil
    }

    /// The pointer for one frame (`retro_input_poll`): pressed at its position
    /// while it is held; a press that began and ended since the previous poll
    /// counts as held at its start for this one frame. Clears the latch.
    /// Emulation thread only; no locks, no allocation.
    func pollPointer() -> PointerSample {
        let latched = pointerLatch.exchange(0, ordering: .relaxed)
        let current = pointerState.load(ordering: .relaxed)
        let state = current & Self.pointerPressed == 0 && latched != 0 ? latched : current
        return PointerSample(position: Self.unpack(state), isPressed: state & Self.pointerPressed != 0)
    }

    private static func pack(_ position: PointerPosition) -> UInt64 {
        UInt64(UInt16(bitPattern: position.x)) | UInt64(UInt16(bitPattern: position.y)) << 16
    }

    private static func unpack(_ state: UInt64) -> PointerPosition {
        PointerPosition(
            x: Int16(bitPattern: UInt16(truncatingIfNeeded: state)),
            y: Int16(bitPattern: UInt16(truncatingIfNeeded: state >> 16))
        )
    }

    private var held: UInt32 {
        touch.load(ordering: .relaxed)
            | controller.load(ordering: .relaxed)
            | keyboard.load(ordering: .relaxed)
    }
}

/// The pointer as the core sees it during one frame.
struct PointerSample: Hashable {
    var position: PointerPosition
    var isPressed: Bool

    static let lifted = PointerSample(position: PointerPosition(x: 0, y: 0), isPressed: false)
}
