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

/// The buttons the core sees on port 0, combined from all input sources.
///
/// Every source keeps its own mask; the core sees their union. A button pressed
/// and released again between two polls still reaches the core for one frame
/// (it is latched until the next `retro_input_poll`). Lock-free: writers and
/// the emulation thread only touch atomics.
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

    public init() {
        fatalError("M1 track K")
    }

    /// Replaces the buttons held through `source`. Callable from any thread,
    /// but only from one writer per source.
    public func set(_ buttons: JoypadButtons, from source: Source) {
        fatalError("M1 track K")
    }

    /// The union of all sources right now, without the latch. For the debug
    /// overlay and tests; the core reads its own snapshot once per frame.
    public var heldButtons: JoypadButtons {
        fatalError("M1 track K")
    }
}
