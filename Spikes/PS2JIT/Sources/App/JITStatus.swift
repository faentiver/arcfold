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

/// Labels of the probes, as the app and probes.json show them.
enum ProbeLabel {
    static let debugger = "Debugger"
    static let stikDebug = "StikDebug öffnen"
    static let localDualMapping = "Lokales Dual-Mapping"
    static let localNewPage = "Lokales Dual-Mapping, zweite Seite"
    static let localRewrite = "Lokales Dual-Mapping, erste Seite neu beschrieben"
    static let debuggerRegion = "universal.js, Region vom Debugger"
    static let selfMapped = "universal.js, eigene r-x-Region"
    static let protectFlip = "Play!s Weg (vm_protect auf r-x)"
    static let detach = "Detach (x16 = 0)"
    static let afterDetachNewPage = "Nach Detach: Region vom Debugger, unbenutzte Seite"
    static let afterDetachRewrite = "Nach Detach: Region vom Debugger, erste Seite neu beschrieben"
}

enum JITProbes {
    /// universal.js prepares memory in 16 KiB pages (StikDebug JSDebugSupport.swift).
    static let pageSize = 16 * 1024

    /// Simulator: the Mac kernel lets the process map r-x and alias it rw-
    /// without a debugger. This says nothing about a device (plan, section 10).
    /// Two pages, so the second one can be probed later like after a detach.
    static func localDualMapping(label: String) -> (probe: JITProbe, region: ArcJITRegion?) {
        var region = ArcJITRegion()
        let (created, message) = callWithMessage { buffer, count in
            ArcJITCreateLocalRegion(2 * pageSize, &region, buffer, count)
        }
        guard created else {
            return (JITProbe(label: label, passed: false, detail: message), nil)
        }
        return (probe(region, page: 0, value: 42, label: label, setup: message), region)
    }

    /// Device: asks universal.js for a region, either allocated by the
    /// debugger (x0 = NULL) or mapped by the app.
    static func debuggerRegion(
        _ source: ArcJITRegionSource, pages: Int, label: String
    ) -> (probe: JITProbe, region: ArcJITRegion?) {
        var region = ArcJITRegion()
        let (prepared, message) = callWithMessage { buffer, count in
            ArcJITPrepareRegion(source, pages * pageSize, &region, buffer, count)
        }
        guard prepared else {
            return (JITProbe(label: label, passed: false, detail: message), nil)
        }
        return (probe(region, page: 0, value: 42, label: label, setup: message), region)
    }

    /// Writes new code into a region probed before and runs it: on an unused
    /// page or over the code of the first probe.
    static func reprobe(_ region: ArcJITRegion, page: Int, value: UInt16, label: String, note: String) -> JITProbe {
        probe(region, page: page, value: value, label: label, setup: note)
    }

    /// Play! 0.77's own path: write, then vm_protect to r-x.
    static func protectFlip(label: String) -> JITProbe {
        var protection: Int32 = 0
        var outcome = ArcJITProbeNotExecutable
        let (_, message) = callWithMessage { buffer, count in
            outcome = ArcJITProbeProtectFlip(&protection, buffer, count)
            return true
        }
        return result(outcome, label: label, value: 42, detail: "\(message); Schutz \(protectionString(protection))")
    }

    static func detach(label: String) -> JITProbe {
        let (detached, message) = callWithMessage { buffer, count in
            ArcJITDetach(buffer, count)
        }
        return JITProbe(label: label, passed: detached, detail: message)
    }

    private static func probe(_ region: ArcJITRegion, page: Int, value: UInt16, label: String, setup: String) -> JITProbe {
        var region = region
        var protection: Int32 = 0
        let outcome = ArcJITProbeRegionAt(&region, page * pageSize, value, &protection)
        return result(outcome, label: label, value: value,
                      detail: "\(setup); Seite \(page + 1), Schutz \(protectionString(protection))")
    }

    private static func result(_ outcome: ArcJITProbeOutcome, label: String, value: UInt16, detail: String) -> JITProbe {
        switch outcome {
        case ArcJITProbePassed:
            return JITProbe(label: label, passed: true, detail: "\(detail); Testfunktion lieferte \(value)")
        case ArcJITProbeWrongResult:
            return JITProbe(label: label, passed: false, detail: "\(detail); falsches Ergebnis statt \(value)")
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
