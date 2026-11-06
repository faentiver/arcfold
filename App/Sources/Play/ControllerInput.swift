import Foundation
import GameController
import LibretroKit
import Observation
import Synchronization

/// Game controllers and a hardware keyboard as input sources (ADR 0005,
/// section 7). Watches connections on the main actor; the button states
/// themselves arrive on a serial queue of their own, so a busy main thread
/// does not delay them.
@Observable
final class ControllerInput {
    /// True while at least one game controller is connected; the touch
    /// controls hide then. A keyboard does not count.
    private(set) var isControllerConnected = false

    @ObservationIgnored private let router: InputRouter
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var keyboardTokens: [NotificationCenter.ObservationToken] = []
    @ObservationIgnored private var isRunning = false

    init(input: InputState) {
        router = InputRouter(input: input)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NotificationCenter.default
        // The notifications only trigger a comparison with the current list,
        // so no controller object has to cross from the notification.
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncControllers()
                }
            })
        }
        keyboardTokens.append(center.addObserver(of: GCKeyboard.self, for: .didConnect) { [weak self] message in
            self?.router.attach(message.keyboard)
        })
        keyboardTokens.append(center.addObserver(of: GCKeyboard.self, for: .didDisconnect) { [weak self] message in
            self?.router.detach(message.keyboard)
        })

        syncControllers()
        if let keyboard = GCKeyboard.coalesced {
            router.attach(keyboard)
        }
    }

    /// Stops listening and releases every button.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        for token in keyboardTokens {
            center.removeObserver(token)
        }
        observers = []
        keyboardTokens = []
        for controller in GCController.controllers() {
            controller.input.inputStateAvailableHandler = nil
        }
        router.sync(with: [])
        if let keyboard = GCKeyboard.coalesced {
            router.detach(keyboard)
        }
        isControllerConnected = false
    }

    private func syncControllers() {
        let controllers = GCController.controllers()
        router.sync(with: controllers)
        isControllerConnected = !controllers.isEmpty
    }
}

/// Turns controller and keyboard states into RetroPad masks. Every handler
/// runs on `queue`, so `InputState` gets exactly one writer per source.
nonisolated final class InputRouter: Sendable {
    private let input: InputState
    private let queue = DispatchQueue(label: "com.faentiver.arcfold.input", qos: .userInteractive)
    /// The mask of each connected controller; the core sees their union.
    private let controllerMasks = Mutex<[ObjectIdentifier: JoypadButtons]>([:])
    /// The controllers with a handler; changed on the main actor only.
    private let attached = Mutex<Set<ObjectIdentifier>>([])

    init(input: InputState) {
        self.input = input
    }

    // MARK: Game controllers

    /// Attaches to new controllers and forgets the masks of the ones that
    /// are gone.
    func sync(with controllers: [GCController]) {
        let current = Set(controllers.map(ObjectIdentifier.init))
        let previous = attached.withLock { attached in
            defer { attached = current }
            return attached
        }
        for controller in controllers where !previous.contains(ObjectIdentifier(controller)) {
            attach(controller)
        }
        for id in previous.subtracting(current) {
            queue.async { [weak self] in
                self?.setController(id, buttons: nil)
            }
        }
    }

    private func attach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        let liveInput = controller.input
        liveInput.queue = queue
        // Keep every intermediate state, so a press shorter than one poll
        // still reaches the latch of InputState.
        liveInput.inputStateQueueDepth = 16
        liveInput.inputStateAvailableHandler = { [weak self] liveInput in
            guard let self else { return }
            while let state = liveInput.nextInputState() {
                self.setController(id, buttons: Self.buttons(in: state))
            }
        }
        let initial = Self.buttons(in: liveInput.capture())
        queue.async { [weak self] in
            self?.setController(id, buttons: initial)
        }
    }

    /// Runs on `queue` only.
    private func setController(_ id: ObjectIdentifier, buttons: JoypadButtons?) {
        let union = controllerMasks.withLock { masks in
            masks[id] = buttons
            return masks.values.reduce(into: JoypadButtons()) { $0.formUnion($1) }
        }
        input.set(union, from: .controller)
    }

    /// RetroPad by position (ADR 0005): the right face button is A, the lower
    /// one B, the left one Y and the upper one X. The GameController names
    /// follow positions too: `.a` is the lower button, `.b` the right one.
    static func buttons(in state: some GCDevicePhysicalInputState) -> JoypadButtons {
        func isPressed(_ name: GCButtonElementName) -> Bool {
            state.buttons[name]?.pressedInput.isPressed ?? false
        }
        var buttons: JoypadButtons = []
        if isPressed(.b) { buttons.insert(.a) }
        if isPressed(.a) { buttons.insert(.b) }
        if isPressed(.x) { buttons.insert(.y) }
        if isPressed(.y) { buttons.insert(.x) }
        if isPressed(.leftShoulder) || isPressed(.leftTrigger) { buttons.insert(.l) }
        if isPressed(.rightShoulder) || isPressed(.rightTrigger) { buttons.insert(.r) }
        if isPressed(.menu) { buttons.insert(.start) }
        if isPressed(.options) { buttons.insert(.select) }
        if let pad = state.dpads[.directionPad] {
            if pad.up.isPressed { buttons.insert(.up) }
            if pad.down.isPressed { buttons.insert(.down) }
            if pad.left.isPressed { buttons.insert(.left) }
            if pad.right.isPressed { buttons.insert(.right) }
        }
        if let stick = state.dpads[.leftThumbstick] {
            buttons.formUnion(stickDirections(x: stick.xAxis.value, y: stick.yAxis.value))
        }
        return buttons
    }

    /// The stick counts as a direction from half its travel on.
    static func stickDirections(x: Float, y: Float) -> JoypadButtons {
        var buttons: JoypadButtons = []
        if y >= 0.5 { buttons.insert(.up) }
        if y <= -0.5 { buttons.insert(.down) }
        if x <= -0.5 { buttons.insert(.left) }
        if x >= 0.5 { buttons.insert(.right) }
        return buttons
    }

    // MARK: Keyboard

    /// The default keyboard of RetroArch (config.def.keybinds.h, user 1):
    /// arrows, X for A, Z for B, S for X, A for Y, Q for L, W for R,
    /// Return for Start and right Shift for Select.
    static let keyboardMap: [(GCKeyCode, JoypadButtons)] = [
        (.upArrow, .up), (.downArrow, .down), (.leftArrow, .left), (.rightArrow, .right),
        (.keyX, .a), (.keyZ, .b), (.keyS, .x), (.keyA, .y),
        (.keyQ, .l), (.keyW, .r), (.returnOrEnter, .start), (.rightShift, .select),
    ]

    func attach(_ keyboard: GCKeyboard) {
        keyboard.handlerQueue = queue
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] keyboardInput, _, _, _ in
            guard let self else { return }
            var buttons: JoypadButtons = []
            for (keyCode, button) in Self.keyboardMap where keyboardInput.button(forKeyCode: keyCode)?.isPressed == true {
                buttons.insert(button)
            }
            self.input.set(buttons, from: .keyboard)
        }
    }

    func detach(_ keyboard: GCKeyboard) {
        keyboard.keyboardInput?.keyChangedHandler = nil
        queue.async { [weak self] in
            self?.input.set([], from: .keyboard)
        }
    }
}
