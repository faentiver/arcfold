import Foundation
import Observation
import UIKit

/// Drives the spike: reads core and JIT state, prepares JIT on a device,
/// boots the test ELF and stores the results in Documents/SpikeResults.
@MainActor
@Observable
final class SpikeModel {
    enum RunState: Equatable {
        case idle
        case waitingForDebugger
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
    private(set) var deviceJITReady = false

    /// Reported to the core as RETRO_ENVIRONMENT_GET_JIT_CAPABLE. In the
    /// simulator the Mac's rules for executable memory apply, so JIT works.
    /// On a device only a passed probe counts, unless the test forces it.
    var forceJITCapable = false

    private let defaults = UserDefaults.standard

    init() {
        do {
            coreInfo = try PS2SpikeHost.loadCoreInfo()
        } catch {
            coreError = error.localizedDescription
        }
        if status.isSimulator {
            probes = [JITProbes.localDualMapping()]
        }
    }

    var jitCapableForCore: Bool {
        if defaults.object(forKey: "jitCapable") != nil {
            return defaults.bool(forKey: "jitCapable")
        }
        return status.isSimulator || deviceJITReady || forceJITCapable
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
    /// overrides the frame count.
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
            probes.append(JITProbe(label: "StikDebug öffnen", passed: false,
                                   detail: "stikdebug:// ließ sich nicht öffnen. Ist StikDebug installiert?"))
            return
        }
        await waitForDebuggerAndPrepare()
    }

    /// Waits up to two minutes for a debugger, then runs the breakpoint
    /// protocol where TXM is assumed. Without TXM the attach alone is enough.
    func waitForDebuggerAndPrepare() async {
        runState = .waitingForDebugger
        defer { if runState == .waitingForDebugger { runState = .idle } }
        for _ in 0..<240 {
            refreshStatus()
            if status.debugged && (status.traced || !status.assumesTXM) { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard status.debugged else {
            probes.append(JITProbe(label: "Debugger", passed: false,
                                   detail: "CS_DEBUGGED kam nicht innerhalb von 120 s"))
            return
        }
        if status.assumesTXM {
            guard status.traced else {
                probes.append(JITProbe(label: "Debugger", passed: false,
                                       detail: "CS_DEBUGGED gesetzt, aber kein Debugger mehr verbunden. Ohne Skript gibt es unter TXM kein JIT."))
                return
            }
            let debuggerRegion = JITProbes.debuggerRegion(ArcJITRegionSourceDebugger)
            let selfMapped = JITProbes.debuggerRegion(ArcJITRegionSourceSelfMapped)
            let detach = JITProbes.detach()
            probes.append(contentsOf: [debuggerRegion, selfMapped, detach])
            deviceJITReady = debuggerRegion.passed || selfMapped.passed
        } else {
            let local = JITProbes.localDualMapping()
            probes.append(local)
            deviceJITReady = local.passed
        }
        refreshStatus()
    }

    private(set) var program: TestProgram?

    /// Boots one test program. libretro allows a single run per process, so
    /// the next test needs a relaunch.
    func boot(_ program: TestProgram) async {
        guard runState != .running, report == nil else { return }
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
        let directory = URL.documentsDirectory.appending(path: "SpikeResults", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = SpikeResult(model: self, report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result) {
            try? data.write(to: directory.appending(path: "report.json"))
        }
        if let compact = try? JSONEncoder().encode(result), let line = String(data: compact, encoding: .utf8) {
            print("ARCFOLD-SPIKE-RESULT \(line)")
        }
        if let png = report.lastFramePNG {
            try? png.write(to: directory.appending(path: "frame.png"))
        }
        try? report.programOutput.write(to: directory.appending(path: "ps2_stdout.txt"),
                                        atomically: true, encoding: .utf8)
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
        let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false)
        let actualLines = output.split(separator: "\n", omittingEmptySubsequences: false)
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
    let framesPerSecond: Double
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
        framesPerSecond = report.seconds > 0 ? Double(report.framesPresented) / report.seconds : 0
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
