import Foundation
import LibretroKit
import Renderer
import SwiftUI

/// One reading of everything the debug overlay shows (ADR 0005, section 9).
/// Snapshots only: reading never blocks the emulation or the audio thread.
nonisolated struct DebugReadings: Sendable {
    var emulation: SessionStats.Snapshot?
    var presentation: PresentationStats.Snapshot
    var mailbox: MailboxCounters?
    var audio: AudioCounters
    /// The core's sample rate, to turn frames into milliseconds.
    var audioSampleRate: Double
    var route: AudioRoute?
    var thermalState: ProcessInfo.ThermalState
    var isLowPowerModeEnabled: Bool

    /// The overlay's lines; also the line the app logs every 10 seconds.
    var lines: [String] {
        [emulationLine, displayLine, audioLine, deviceLine]
    }

    var emulationLine: String {
        guard let emulation else { return "Emulation –" }
        return "Emulation \(Self.number(emulation.framesPerSecond, digits: 2)) fps"
            + " · run \(Self.milliseconds(emulation.lastRunTime)) ms (max \(Self.milliseconds(emulation.maxRunTime)))"
            + " · trim \(Self.number(emulation.periodTrim * 100, digits: 3)) %"
            + " · late \(emulation.lateFrames) · resync \(emulation.resyncs)"
    }

    var displayLine: String {
        var line = "Display \(Self.number(presentation.refreshRate, digits: 0)) Hz"
            + " · shown \(presentation.framesShown) · repeated \(presentation.framesRepeated)"
            + " · skipped \(presentation.framesSkipped) · late \(presentation.lateSelections)"
            + " · GPU busy \(presentation.gpuBusy)"
        if let mailbox {
            line += " · overwritten \(mailbox.overwritten)"
        }
        return line
    }

    var audioLine: String {
        let perMillisecond = audioSampleRate / 1000
        let buffered = perMillisecond > 0 ? Double(audio.bufferedFrames) / perMillisecond : 0
        let target = perMillisecond > 0 ? Double(audio.targetFrames) / perMillisecond : 0
        var line = "Audio \(Self.number(buffered, digits: 1)) ms (target \(Self.number(target, digits: 1)))"
            + " · underruns \(audio.underruns) · dropped \(audio.droppedFrames) · primes \(audio.primes)"
        if let route {
            line += " · IO \(Self.number(route.ioBufferDuration * 1000, digits: 1)) ms"
                + " · \(Self.number(route.hardwareSampleRate, digits: 0)) Hz"
        }
        return line
    }

    var deviceLine: String {
        "Thermal \(Self.name(of: thermalState)) · Low Power \(isLowPowerModeEnabled ? "on" : "off")"
    }

    private static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return number(Double(seconds) * 1000 + Double(attoseconds) / 1e15, digits: 2)
    }

    private static func name(of state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// Measurements over the picture, refreshed four times a second. Technical
/// text for development and acceptance runs, so it is not localized.
struct DebugOverlay: View {
    /// Called on every refresh; must only read snapshots.
    let read: () -> DebugReadings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let readings = read()
            VStack(alignment: .leading, spacing: 2) {
                ForEach(readings.lines, id: \.self) { line in
                    Text(verbatim: line)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("debug-overlay")
        }
        .allowsHitTesting(false)
    }

    /// On in debug builds, off in release builds; the game menu switches it.
    static var isOnByDefault: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

#Preview {
    DebugOverlay {
        DebugReadings(
            emulation: SessionStats.Snapshot(
                framesEmulated: 3584, framesPerSecond: 59.73, lateFrames: 0, resyncs: 0,
                lastRunTime: .microseconds(420), maxRunTime: .microseconds(1100),
                maxLateness: .microseconds(800), periodTrim: -0.00012),
            presentation: PresentationStats.Snapshot(
                displayUpdates: 7200, refreshRate: 120, framesShown: 3583, framesRepeated: 3617,
                framesSkipped: 0, lateSelections: 0, gpuBusy: 0),
            mailbox: MailboxCounters(published: 3584, overwritten: 0),
            audio: AudioCounters(
                underruns: 0, underrunFrames: 0, droppedFrames: 0, primes: 1, renderCalls: 12_000,
                largestRequest: 164, bufferedFrames: 1130, targetFrames: 1147),
            audioSampleRate: 32768,
            route: AudioRoute(hardwareSampleRate: 48000, ioBufferDuration: 0.0053, outputLatency: 0.012),
            thermalState: .nominal,
            isLowPowerModeEnabled: false
        )
    }
    .padding()
    .background(.gray)
}
