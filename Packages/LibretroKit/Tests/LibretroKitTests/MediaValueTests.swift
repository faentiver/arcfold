import CLibretro
import LibretroKit
import Testing

/// The value types of the public API that both M1 tracks build on (ADR 0005).
struct MediaValueTests {
    @Test func joypadButtonsUseTheRetroPadBitNumbers() {
        let buttons: [(JoypadButtons, Int32)] = [
            (.b, RETRO_DEVICE_ID_JOYPAD_B), (.y, RETRO_DEVICE_ID_JOYPAD_Y),
            (.select, RETRO_DEVICE_ID_JOYPAD_SELECT), (.start, RETRO_DEVICE_ID_JOYPAD_START),
            (.up, RETRO_DEVICE_ID_JOYPAD_UP), (.down, RETRO_DEVICE_ID_JOYPAD_DOWN),
            (.left, RETRO_DEVICE_ID_JOYPAD_LEFT), (.right, RETRO_DEVICE_ID_JOYPAD_RIGHT),
            (.a, RETRO_DEVICE_ID_JOYPAD_A), (.x, RETRO_DEVICE_ID_JOYPAD_X),
            (.l, RETRO_DEVICE_ID_JOYPAD_L), (.r, RETRO_DEVICE_ID_JOYPAD_R),
            (.l2, RETRO_DEVICE_ID_JOYPAD_L2), (.r2, RETRO_DEVICE_ID_JOYPAD_R2),
            (.l3, RETRO_DEVICE_ID_JOYPAD_L3), (.r3, RETRO_DEVICE_ID_JOYPAD_R3),
        ]
        for (button, id) in buttons {
            #expect(button.rawValue == UInt32(1) << UInt32(id))
        }
        #expect(buttons.map(\.0).reduce(JoypadButtons()) { $0.union($1) }.rawValue == 0xFFFF)
    }

    @Test func pixelFormatsKnowTheirSize() {
        #expect(PixelFormat.rgb565.bytesPerPixel == 2)
        #expect(PixelFormat.rgb1555.bytesPerPixel == 2)
        #expect(PixelFormat.xrgb8888.bytesPerPixel == 4)
    }
}
