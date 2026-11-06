@testable import Arcfold
import GameController
import LibretroKit
import Testing

/// What controllers and the keyboard press on the RetroPad (ADR 0005, section 7).
struct InputMappingTests {
    @Test func theStickCountsFromHalfItsTravel() {
        #expect(InputRouter.stickDirections(x: 0, y: 0).isEmpty)
        #expect(InputRouter.stickDirections(x: 0.49, y: -0.49).isEmpty)
        #expect(InputRouter.stickDirections(x: 0.5, y: 0) == .right)
        #expect(InputRouter.stickDirections(x: -0.8, y: 0.6) == [.left, .up])
        #expect(InputRouter.stickDirections(x: 0.2, y: -1) == .down)
    }

    /// RetroArch's default keyboard for user 1 (config.def.keybinds.h).
    @Test func theKeyboardFollowsRetroArch() {
        let map = Dictionary(uniqueKeysWithValues: InputRouter.keyboardMap.map { ($0.0, $0.1) })
        #expect(map[.keyX] == .a)
        #expect(map[.keyZ] == .b)
        #expect(map[.keyS] == .x)
        #expect(map[.keyA] == .y)
        #expect(map[.keyQ] == .l)
        #expect(map[.keyW] == .r)
        #expect(map[.returnOrEnter] == .start)
        #expect(map[.rightShift] == .select)
        #expect(map[.upArrow] == .up)
        #expect(map[.downArrow] == .down)
        #expect(map[.leftArrow] == .left)
        #expect(map[.rightArrow] == .right)
        #expect(map.count == 12)
    }
}
