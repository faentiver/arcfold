@testable import LibretroKit
import Testing

/// The shared input state (ADR 0005, section 7): union of the sources and the
/// latch that keeps short presses.
struct InputStateTests {
    @Test func theCoreSeesTheUnionOfAllSources() {
        let input = InputState()
        input.set([.a, .up], from: .touch)
        input.set(.b, from: .controller)
        input.set(.start, from: .keyboard)

        #expect(input.heldButtons == [.a, .up, .b, .start])
        #expect(input.poll() == JoypadButtons([.a, .up, .b, .start]).rawValue)

        // Releasing one source keeps what the others hold.
        input.set([], from: .controller)
        #expect(input.heldButtons == [.a, .up, .start])
        #expect(input.poll() == JoypadButtons([.a, .up, .start]).rawValue)
    }

    @Test func aPressBetweenTwoPollsLastsExactlyOneFrame() {
        let input = InputState()
        #expect(input.poll() == 0)

        input.set(.a, from: .touch)
        input.set([], from: .touch)

        #expect(input.heldButtons.isEmpty)
        #expect(input.poll() == JoypadButtons.a.rawValue)
        #expect(input.poll() == 0)
    }

    @Test func aHeldButtonStaysUntilItIsReleased() {
        let input = InputState()
        input.set(.r, from: .controller)
        #expect(input.poll() == JoypadButtons.r.rawValue)
        #expect(input.poll() == JoypadButtons.r.rawValue)

        input.set([], from: .controller)
        #expect(input.poll() == 0)
    }

    @Test func pressingAgainBeforeThePollIsSeenOnce() {
        let input = InputState()
        input.set(.b, from: .keyboard)
        _ = input.poll()
        input.set([], from: .keyboard)
        input.set(.b, from: .keyboard)
        input.set([], from: .keyboard)
        #expect(input.poll() == JoypadButtons.b.rawValue)
        #expect(input.poll() == 0)
    }

    @Test func countsEveryPressAndKeepsTheLatest() {
        let input = InputState()
        #expect(input.pressCount == 0)
        #expect(input.lastPressedButtons.isEmpty)

        input.set(.a, from: .touch)
        // Sliding from A to B: B goes down while A is still held, then A goes up.
        input.set([.a, .b], from: .touch)
        input.set(.b, from: .touch)
        input.set([], from: .touch)
        #expect(input.pressCount == 2)
        #expect(input.lastPressedButtons == .b, "The latest press stays after the release")

        // Two buttons at once count twice; each source counts on its own.
        input.set([.up, .start], from: .controller)
        input.set(.start, from: .keyboard)
        #expect(input.pressCount == 5)
        #expect(input.lastPressedButtons == .start)
    }

    // MARK: Pointer (ADR 0006)

    @Test func thePointerIsPressedWhereItWasSetUntilItIsLifted() {
        let input = InputState()
        #expect(input.pointer == nil)
        #expect(input.pollPointer() == .lifted)

        let corner = PointerPosition(x: -32_767, y: 32_767)
        input.setPointer(corner)
        #expect(input.pointer == corner)
        #expect(input.pollPointer() == PointerSample(position: corner, isPressed: true))
        #expect(input.pollPointer() == PointerSample(position: corner, isPressed: true))

        // A finger that slides moves the pointer without a new press.
        let moved = PointerPosition(x: 128, y: -1)
        input.setPointer(moved)
        #expect(input.pollPointer() == PointerSample(position: moved, isPressed: true))
        #expect(input.pointerPressCount == 1)

        // Lifted, it keeps its last coordinates.
        input.setPointer(nil)
        #expect(input.pointer == nil)
        #expect(input.pollPointer() == PointerSample(position: moved, isPressed: false))
    }

    @Test func aTouchBetweenTwoPollsLastsExactlyOneFrameAtItsStart() {
        let input = InputState()
        let start = PointerPosition(x: 1_000, y: 17_066)
        input.setPointer(start)
        input.setPointer(PointerPosition(x: 1_200, y: 17_100))
        input.setPointer(nil)

        #expect(input.pointer == nil)
        #expect(input.pollPointer() == PointerSample(position: start, isPressed: true))
        #expect(input.pollPointer().isPressed == false)
    }

    @Test func countsPointerPressesAndKeepsWhereTheLatestBegan() {
        let input = InputState()
        #expect(input.pointerPressCount == 0)
        #expect(input.lastPointerPress == nil)

        let first = PointerPosition(x: -100, y: 200)
        input.setPointer(first)
        input.setPointer(PointerPosition(x: -90, y: 210))
        input.setPointer(nil)
        let second = PointerPosition(x: 5, y: 6)
        input.setPointer(second)
        input.setPointer(nil)

        #expect(input.pointerPressCount == 2)
        #expect(input.lastPointerPress == second, "The start of the latest press stays after the release")
        // Buttons count on their own.
        #expect(input.pressCount == 0)
    }

    @Test func writersOnSeveralThreadsNeverLoseAButton() async {
        let input = InputState()
        await withTaskGroup { group in
            for source in InputState.Source.allCases {
                group.addTask {
                    for index in 0..<10_000 {
                        input.set(index.isMultiple(of: 2) ? .select : [], from: source)
                    }
                    input.set(source == .touch ? .l : .select, from: source)
                }
            }
        }
        #expect(input.heldButtons == [.l, .select])
    }
}
