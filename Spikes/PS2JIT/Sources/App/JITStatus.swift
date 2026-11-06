import Foundation

/// Snapshot of what the process knows about its ability to run JIT code.
struct JITStatus: Equatable, Sendable {
    let isSimulator: Bool
    let hardwareIdentifier: String
    let osVersion: String
    let getTaskAllow: Bool
    let debugged: Bool
    let traced: Bool
    let csopsResult: Int32
    let assumesTXM: Bool

    static func current() -> JITStatus {
        let process = ArcJITReadProcessStatus()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let hardware = hardwareIdentifier()
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return JITStatus(
            isSimulator: isSimulator,
            hardwareIdentifier: hardware,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            getTaskAllow: process.getTaskAllow,
            debugged: process.debugged,
            traced: process.traced,
            csopsResult: process.csopsResult,
            assumesTXM: !isSimulator && ArcJITAssumesTXM(hardware, Int32(version.majorVersion))
        )
    }

    private static func hardwareIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// One attempt to get an executable page and run code from it.
struct JITProbe: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let passed: Bool
    let detail: String
}

enum JITProbes {
    static let probeSize = 16 * 1024

    /// Simulator: the Mac kernel lets the process map r-x and alias it rw-
    /// without a debugger. This says nothing about a device (plan, section 10).
    static func localDualMapping() -> JITProbe {
        let label = "Lokales Dual-Mapping"
        var region = ArcJITRegion()
        let (created, message) = callWithMessage { buffer, count in
            ArcJITCreateLocalRegion(probeSize, &region, buffer, count)
        }
        guard created else {
            return JITProbe(label: label, passed: false, detail: message)
        }
        return probe(region, label: label, setup: message)
    }

    /// Device: asks universal.js for a region, either allocated by the
    /// debugger (x0 = NULL) or mapped by the app.
    static func debuggerRegion(_ source: ArcJITRegionSource) -> JITProbe {
        let label = source == ArcJITRegionSourceDebugger
            ? "universal.js, Region vom Debugger"
            : "universal.js, eigene r-x-Region"
        var region = ArcJITRegion()
        let (prepared, message) = callWithMessage { buffer, count in
            ArcJITPrepareRegion(source, probeSize, &region, buffer, count)
        }
        guard prepared else {
            return JITProbe(label: label, passed: false, detail: message)
        }
        return probe(region, label: label, setup: message)
    }

    static func detach() -> JITProbe {
        let (detached, message) = callWithMessage { buffer, count in
            ArcJITDetach(buffer, count)
        }
        return JITProbe(label: "Detach (x16 = 0)", passed: detached, detail: message)
    }

    private static func probe(_ region: ArcJITRegion, label: String, setup: String) -> JITProbe {
        var region = region
        var protection: Int32 = 0
        let outcome = ArcJITProbeRegion(&region, &protection)
        let detail = "\(setup); Schutz \(protectionString(protection))"
        switch outcome {
        case ArcJITProbePassed:
            return JITProbe(label: label, passed: true, detail: "\(detail); Testfunktion lieferte 42")
        case ArcJITProbeWrongResult:
            return JITProbe(label: label, passed: false, detail: "\(detail); falsches Ergebnis")
        default:
            return JITProbe(label: label, passed: false, detail: "\(detail); Seite nicht ausführbar")
        }
    }

    private static func protectionString(_ protection: Int32) -> String {
        guard protection >= 0 else { return "unbekannt" }
        let read = protection & 1 != 0 ? "r" : "-"
        let write = protection & 2 != 0 ? "w" : "-"
        let execute = protection & 4 != 0 ? "x" : "-"
        return read + write + execute
    }

    /// Calls a C function that reports its outcome as text in a caller-owned buffer.
    private static func callWithMessage(
        _ body: (UnsafeMutablePointer<CChar>, Int) -> Bool
    ) -> (Bool, String) {
        var buffer = [CChar](repeating: 0, count: 256)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            body(pointer.baseAddress!, pointer.count)
        }
        let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return (result, text)
    }
}
