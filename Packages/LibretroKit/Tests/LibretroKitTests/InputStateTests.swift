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
