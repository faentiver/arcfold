import Foundation
import Observation
import OSLog
import UIKit

/// Drives the spike: reads core and JIT state, prepares JIT on a device,
/// boots the test ELF and stores the results in Documents/SpikeResults.
@MainActor
@Observable
final class SpikeModel {
    enum RunState: Equatable {
        case idle
        case waitingForDebugger
        case probing
        case running
        case finished
    }

    private(set) var coreInfo: PS2CoreInfo?
    private(set) var coreError: String?
    private(set) var status = JITStatus.current()
    private(set) var probes: [JITProbe] = []
    private(set) var runState = RunState.idle
    private(set) var report: PS2RunReport?
    private(set) var outputCheck: OutputCheck?
    /// A region prepared through the debugger worked (what a TXM device needs).
    private(set) var arenaJITReady = false
    /// Play!'s own vm_protect path worked (enough for an unpatched core).
    private(set) var protectJITReady = false

    /// Where this launch keeps probes.json, report.json, frame.png and ps2_stdout.txt.
    let results: ResultStore

    /// The region universal.js prepared for the first device probe. It stays
    /// mapped, so its pages can be probed again after a detach.
    @ObservationIgnored private var debuggerRegion: ArcJITRegion?

    /// Lets the test start the core although no suitable JIT path passed,
    /// to watch what happens without one.
    var forceJITCapable = false

    private let defaults = UserDefaults.standard
    private static let log = Logger(subsystem: "com.faentiver.arcfold.spike.jit", category: "spike")

    init() {
        results = ResultStore(requestedName: UserDefaults.standard.string(forKey: "resultsName"))
        do {
            coreInfo = try PS2SpikeHost.loadCoreInfo()
        } catch {
            coreError = error.localizedDescription
        }
        if status.isSimulator {
            runSimulatorProbes()
        }
    }

    /// The variant built by try-codegen-pr34.sh asks the debugger for one JIT
    /// arena (Play--CodeGen PR #34); upstream Play! 0.77 flips page rights.
    var coreUsesTXMArena: Bool {
        coreInfo?.libraryVersion.hasSuffix("-pr34") ?? false
    }

    /// Answer to RETRO_ENVIRONMENT_GET_JIT_CAPABLE. In the simulator the Mac's
    /// rules for executable memory apply, so JIT works. On a device it depends
    /// on whether the probe for the core's own allocation path passed.
    var jitCapableForCore: Bool {
        if defaults.object(forKey: "jitCapable") != nil {
            return defaults.bool(forKey: "jitCapable")
        }
        if status.isSimulator || forceJITCapable {
            return true
        }
        return coreUsesTXMArena ? arenaJITReady : protectJITReady
    }

    /// Frames for the drawing test; 600 are ten seconds at full speed.
    var spriteFrames = 600

    private(set) var thermalBefore: ProcessInfo.ThermalState?
    private(set) var thermalAfter: ProcessInfo.ThermalState?

    func refreshStatus() {
        status = JITStatus.current()
    }

    /// Launch arguments: `-autorun YES` boots a test right away, `-program
    /// gs_sprites` picks the drawing test instead of alu, `-maxFrames N`
    /// overrides the frame count, `-resultsName NAME` names the results folder.
    func autorunIfRequested() async {
        guard defaults.bool(forKey: "autorun"), runState == .idle else { return }
        let program = TestProgram(rawValue: defaults.string(forKey: "program") ?? "") ?? .alu
        await boot(program)
    }

    /// Opens StikDebug with this app's PID and the universal script
    /// (StikJIT INTEGRATION.md, part 2), then waits for the debugger.
    func requestJITFromStikDebug() async {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        components.queryItems = [
            URLQueryItem(name: "bundle-id", value: bundleID),
            URLQueryItem(name: "pid", value: String(getpid())),
        ]
        if status.assumesTXM {
            components.queryItems?.append(URLQueryItem(name: "script-name", value: "universal.js"))
        }
        guard let url = components.url else { return }
        let opened = await UIApplication.shared.open(url)
        guard opened else {
            record(ProbeLabel.stikDebug) {
                JITProbe(label: $0, passed: false, detail: "stikdebug:// ließ sich nicht öffnen. Ist StikDebug installiert?")
            }
            return
        }
        await waitForDebuggerAndPrepare()
    }

    /// Waits up to two minutes for a debugger, then probes every JIT path,
    /// one after the other and each saved right away. Where TXM is assumed it
    /// runs the breakpoint protocol and leaves the script attached: the PR #34
    /// core asks for its arena only when it compiles the first block, and a
    /// later request after a detach would trap without a handler.
    func waitForDebuggerAndPrepare() async {
        runState = .waitingForDebugger
        defer { runState = .idle }
        for _ in 0..<240 {
            refreshStatus()
            if status.debugged && (status.traced || !status.assumesTXM) { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard status.debugged else {
            record(ProbeLabel.debugger) { JITProbe(label: $0, passed: false, detail: "CS_DEBUGGED kam nicht innerhalb von 120 s") }
            return
        }
        runState = .probing
        if status.assumesTXM {
            guard status.traced else {
                record(ProbeLabel.debugger) {
                    JITProbe(label: $0, passed: false,
                             detail: "CS_DEBUGGED gesetzt, aber kein Debugger mehr verbunden. Ohne Skript gibt es unter TXM kein JIT.")
                }
                return
            }
            // The central question first: does a region from universal.js run code?
            var prepared: ArcJITRegion?
            let central = record(ProbeLabel.debuggerRegion) { label in
                let outcome = JITProbes.debuggerRegion(ArcJITRegionSourceDebugger, pages: 2, label: label)
                prepared = outcome.region
                return outcome.probe
            }
            debuggerRegion = prepared
            arenaJITReady = central.passed
            await pauseForDisplay()
            record(ProbeLabel.selfMapped) { JITProbes.debuggerRegion(ArcJITRegionSourceSelfMapped, pages: 1, label: $0).probe }
            await pauseForDisplay()
            protectJITReady = record(ProbeLabel.protectFlip) { JITProbes.protectFlip(label: $0) }.passed
        } else {
            protectJITReady = record(ProbeLabel.protectFlip) { JITProbes.protectFlip(label: $0) }.passed
            await pauseForDisplay()
            arenaJITReady = record(ProbeLabel.localDualMapping) { JITProbes.localDualMapping(label: $0).probe }.passed
        }
        refreshStatus()
    }

    /// Ends the universal.js session (x16 = 0), then writes new code into the
    /// region of the first probe and runs it: on its unused second page and
    /// over the first page. That answers whether prepared pages stay usable
    /// without the debugger. StikJIT's INTEGRATION.md detaches before JIT is
    /// ready; Play--CodeGen PR #34 never detaches because, it says, execution
    /// depends on the debugger staying attached.
    func detachDebugger() async {
        runState = .probing
        defer { runState = .idle }
        let detach = record(ProbeLabel.detach) { JITProbes.detach(label: $0) }
        guard detach.passed else {
            refreshStatus()
            return
        }
        // P_TRACED clears once debugserver has let go of the process.
        for _ in 0..<20 {
            refreshStatus()
            if !status.traced { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let region = debuggerRegion else { return }
        let note = status.traced ? "P_TRACED noch gesetzt" : "Debugger getrennt, P_TRACED aus"
        record(ProbeLabel.afterDetachNewPage) { JITProbes.reprobe(region, page: 1, value: 43, label: $0, note: note) }
        await pauseForDisplay()
        record(ProbeLabel.afterDetachRewrite) { JITProbes.reprobe(region, page: 0, value: 44, label: $0, note: note) }
        refreshStatus()
    }

    /// Simulator: the Mac's rules apply, so these probes only check the probe
    /// code itself, including the reprobe that a device runs after a detach.
    private func runSimulatorProbes() {
        var local: ArcJITRegion?
        let first = record(ProbeLabel.localDualMapping) { label in
            let outcome = JITProbes.localDualMapping(label: label)
            local = outcome.region
            return outcome.probe
        }
        if first.passed, let local {
            record(ProbeLabel.localNewPage) { JITProbes.reprobe(local, page: 1, value: 43, label: $0, note: "ohne Debugger") }
            record(ProbeLabel.localRewrite) { JITProbes.reprobe(local, page: 0, value: 44, label: $0, note: "ohne Debugger") }
        }
        record(ProbeLabel.protectFlip) { JITProbes.protectFlip(label: $0) }
    }

    /// Runs one probe and saves it at once. A pending entry goes to
    /// probes.json first, so the file still names the probe if it kills the app.
    @discardableResult
    private func record(_ label: String, _ run: (String) -> JITProbe) -> JITProbe {
        results.saveProbes(probes, pending: label)
        let probe = run(label)
        probes.append(probe)
        results.saveProbes(probes, pending: nil)
        Self.log.notice("probe \(probe.passed ? "OK" : "FEHLER", privacy: .public) \(probe.label, privacy: .public): \(probe.detail, privacy: .public)")
        return probe
    }

    /// Lets SwiftUI show a probe before the next one starts.
    private func pauseForDisplay() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    private(set) var program: TestProgram?

    /// Boots one test program. libretro allows a single run per process, so
    /// the next test needs a relaunch.
    func boot(_ program: TestProgram) async {
        guard runState == .idle, report == nil else { return }
        guard let elf = Bundle.main.url(forResource: program.rawValue, withExtension: "elf") else {
            coreError = "\(program.rawValue).elf fehlt im App-Bundle"
            return
        }
        self.program = program
        runState = .running
        thermalBefore = ProcessInfo.processInfo.thermalState
        let requestedFrames = defaults.integer(forKey: "maxFrames")
        let frames = requestedFrames > 0 ? requestedFrames : (program == .alu ? 600 : spriteFrames)
        let report = await PS2SpikeHost.runELF(
            atPath: elf.path,
            maxFrames: frames,
            stopMarker: program == .alu ? "-- TEST END" : nil,
            timeout: program == .alu ? 60 : Double(frames) / 10 + 60,
            jitCapable: jitCapableForCore
        )
        thermalAfter = ProcessInfo.processInfo.thermalState
        self.report = report
        outputCheck = program == .alu && report.gameLoaded ? OutputCheck(output: report.programOutput) : nil
        runState = .finished
        refreshStatus()
        saveResults(report)
    }

    private func saveResults(_ report: PS2RunReport) {
        let result = SpikeResult(model: self, report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(result) {
            results.save(data, as: "report.json")
        }
        // A run without a frame leaves no frame.png; the folder is new for every launch.
        if let png = report.lastFramePNG {
            results.save(png, as: "frame.png")
        }
        results.save(Data(report.programOutput.utf8), as: "ps2_stdout.txt")
        Self.log.notice("run finished, results in SpikeResults/\(self.results.name, privacy: .public)")
    }
}

/// Compares the program's stdout with alu.expected from the fixtures.
struct OutputCheck: Sendable {
    let matches: Bool
    let expectedLines: Int
    let actualLines: Int
    let firstDifference: String?

    init(output: String) {
        let expected = Bundle.main.url(forResource: "alu", withExtension: "expected")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let expectedLines = Self.lines(of: expected)
        let actualLines = Self.lines(of: output)
        self.expectedLines = expectedLines.count
        self.actualLines = actualLines.count
        matches = !expected.isEmpty && expected == output
        if matches {
            firstDifference = nil
        } else if let index = zip(expectedLines, actualLines).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
            firstDifference = "Zeile \(index + 1): erwartet „\(expectedLines[index])“, erhalten „\(actualLines[index])“"
        } else {
            firstDifference = "Längen unterschiedlich: \(expectedLines.count) erwartet, \(actualLines.count) erhalten"
        }
    }

    /// Lines as `wc -l` counts them: a final line break ends the last line.
    private static func lines(of text: String) -> [Substring] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if text.isEmpty || text.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }
}

/// The two test programs from Tests/Fixtures/ps2.
enum TestProgram: String, CaseIterable, Sendable {
    /// ps2autotests EE ALU test: checks the recompiler against alu.expected.
    case alu
    /// Arcfold's own drawing test: five sprites per frame, for image and frame rate.
    case gsSprites = "gs_sprites"
}

extension ProcessInfo.ThermalState {
    var name: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// What the run script collects, also written to Documents/SpikeResults/report.json.
struct SpikeResult: Codable {
    let date: Date
    let results: String
    let program: String
    let device: String
    let osVersion: String
    let simulator: Bool
    let library: String
    let version: String
    let extensions: String
    let getTaskAllow: Bool
    let debugged: Bool
    let traced: Bool
    let assumesTXM: Bool
    let probes: [String]
    let reportedJITCapable: Bool
    let gameLoaded: Bool
    let coreMessage: String?
    let requestedContext: String
    let glRenderer: String
    let retroRunCalls: Int
    let framesPresented: Int
    let seconds: Double
    let framesPerSecond: Double?
    let endReason: String
    let frameSize: String
    let audioFrames: Int
    let thermalStateBefore: String
    let thermalStateAfter: String
    let outputMatchesExpected: Bool?
    let outputLines: Int?
    let expectedLines: Int?
    let firstDifference: String?
    let error: String?

    @MainActor
    init(model: SpikeModel, report: PS2RunReport) {
        let check = model.outputCheck
        date = Date()
        results = "SpikeResults/\(model.results.name)"
        program = model.program?.rawValue ?? ""
        device = model.status.hardwareIdentifier
        osVersion = model.status.osVersion
        simulator = model.status.isSimulator
        library = model.coreInfo?.libraryName ?? ""
        version = model.coreInfo?.libraryVersion ?? ""
        extensions = model.coreInfo?.validExtensions ?? ""
        getTaskAllow = model.status.getTaskAllow
        debugged = model.status.debugged
        traced = model.status.traced
        assumesTXM = model.status.assumesTXM
        probes = model.probes.map { "\($0.passed ? "OK" : "FEHLER") \($0.label): \($0.detail)" }
        reportedJITCapable = report.reportedJITCapable
        gameLoaded = report.gameLoaded
        coreMessage = report.coreMessage
        requestedContext = report.requestedContext
        glRenderer = report.glRenderer
        retroRunCalls = report.retroRunCalls
        framesPresented = report.framesPresented
        seconds = report.seconds
        framesPerSecond = report.retroRunCalls > 0 && report.seconds > 0
            ? Double(report.framesPresented) / report.seconds : nil
        endReason = report.endReason
        frameSize = "\(report.frameWidth)x\(report.frameHeight)"
        audioFrames = report.audioFrames
        thermalStateBefore = model.thermalBefore?.name ?? ""
        thermalStateAfter = model.thermalAfter?.name ?? ""
        outputMatchesExpected = check?.matches
        outputLines = check?.actualLines
        expectedLines = check?.expectedLines
        firstDifference = check?.firstDifference
        error = report.error
    }
}
