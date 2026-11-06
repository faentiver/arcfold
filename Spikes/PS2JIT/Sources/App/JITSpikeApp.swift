import SwiftUI

@main
struct JITSpikeApp: App {
    @State private var model = SpikeModel()

    var body: some Scene {
        WindowGroup {
            SpikeView(model: model)
                .task { await model.autorunIfRequested() }
        }
    }
}

struct SpikeView: View {
    @Bindable var model: SpikeModel

    var body: some View {
        NavigationStack {
            List {
                if let report = model.report {
                    ReportSection(report: report, check: model.outputCheck,
                                  thermalBefore: model.thermalBefore, thermalAfter: model.thermalAfter)
                }
                coreSection
                jitSection
                if !model.status.isSimulator {
                    deviceSection
                }
                runSection
            }
            .navigationTitle("JIT-Spike")
            .refreshable { model.refreshStatus() }
        }
    }

    private var coreSection: some View {
        Section("Kern") {
            if let info = model.coreInfo {
                LabeledContent("Name", value: info.libraryName)
                LabeledContent("Version", value: info.libraryVersion)
                LabeledContent("Endungen", value: info.validExtensions)
                LabeledContent("libretro-API", value: "\(info.apiVersion)")
            } else {
                Text(model.coreError ?? "Kern nicht geladen").foregroundStyle(.red)
            }
        }
    }

    private var jitSection: some View {
        Section {
            LabeledContent("Gerät", value: "\(model.status.hardwareIdentifier), iOS \(model.status.osVersion)")
            LabeledContent("Umgebung", value: model.status.isSimulator ? "Simulator (Regeln des Macs)" : "Gerät")
            StatusRow(title: "get-task-allow", active: model.status.getTaskAllow)
            StatusRow(title: "CS_DEBUGGED", active: model.status.debugged)
            StatusRow(title: "Debugger verbunden (P_TRACED)", active: model.status.traced)
            StatusRow(title: "TXM angenommen", active: model.status.assumesTXM)
            ForEach(model.probes) { probe in
                VStack(alignment: .leading, spacing: 2) {
                    Label(probe.label, systemImage: probe.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(probe.passed ? .green : .red)
                    Text(probe.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("JIT")
        } footer: {
            if model.status.isSimulator {
                Text("Im Simulator gelten die Regeln des Macs für ausführbaren Speicher. Das sagt nichts über JIT auf dem Gerät.")
            }
        }
    }

    private var deviceSection: some View {
        Section {
            Button("JIT über StikDebug anfordern") {
                Task { await model.requestJITFromStikDebug() }
            }
            .disabled(model.runState != .idle)
            Button("Auf Debugger warten (StikDebug von Hand)") {
                Task { await model.waitForDebuggerAndPrepare() }
            }
            .disabled(model.runState != .idle)
            if model.runState == .waitingForDebugger {
                ProgressView("Warte auf den Debugger …")
            }
            Toggle("Kern trotzdem starten (Absturz erwartet)", isOn: $model.forceJITCapable)
        } header: {
            Text("Gerätetest")
        } footer: {
            Text("Ohne JIT meldet der Kern „Cannot run without JIT“ und startet nicht. Der Schalter gibt dem Kern trotzdem JIT frei, um das Verhalten ohne passenden Speicher zu beobachten.")
        }
    }

    private var runSection: some View {
        Section {
            LabeledContent("JIT an den Kern gemeldet", value: model.jitCapableForCore ? "ja" : "nein")
            Button("alu.elf starten (CPU-Test)") {
                Task { await model.boot(.alu) }
            }
            .disabled(!canStart)
            Picker("Bilder für gs_sprites", selection: $model.spriteFrames) {
                Text("600 (10 s)").tag(600)
                Text("3600 (1 min)").tag(3600)
                Text("18000 (5 min)").tag(18000)
            }
            Button("gs_sprites.elf starten (Bild und Bildrate)") {
                Task { await model.boot(.gsSprites) }
            }
            .disabled(!canStart)
            if model.runState == .running {
                ProgressView("Läuft …")
            }
        } header: {
            Text("Lauf")
        } footer: {
            Text("Pro App-Start ist ein Lauf möglich. Für den zweiten Test die App neu starten.")
        }
    }

    private var canStart: Bool {
        model.runState != .running && model.report == nil && model.coreInfo != nil
    }
}

private struct StatusRow: View {
    let title: String
    let active: Bool

    var body: some View {
        LabeledContent(title) {
            Image(systemName: active ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(active ? .green : .secondary)
                .accessibilityLabel(active ? "ja" : "nein")
        }
    }
}

private struct ReportSection: View {
    let report: PS2RunReport
    let check: OutputCheck?
    let thermalBefore: ProcessInfo.ThermalState?
    let thermalAfter: ProcessInfo.ThermalState?

    private var endReasonText: String {
        switch report.endReason {
        case "marker": "Testende in der Ausgabe"
        case "frames": "Bildzahl erreicht"
        case "timeout": "Zeitlimit"
        default: report.endReason
        }
    }

    var body: some View {
        Section("Ergebnis") {
            LabeledContent("Spiel geladen", value: report.gameLoaded ? "ja" : "nein")
            if let message = report.coreMessage {
                LabeledContent("Meldung des Kerns", value: message)
            }
            if !report.gameLoaded && !report.reportedJITCapable {
                Label("PS2 läuft nur mit JIT. App neu starten, zuerst JIT über StikDebug anfordern, dann den Test starten.",
                      systemImage: "bolt.slash")
                    .foregroundStyle(.orange)
            }
            if let error = report.error {
                LabeledContent("Fehler", value: error)
            }
            if report.gameLoaded {
                LabeledContent("Kontext", value: report.requestedContext)
                LabeledContent("GL", value: report.glRenderer)
                LabeledContent("retro_run", value: "\(report.retroRunCalls) in \(report.seconds.formatted(.number.precision(.fractionLength(2)))) s")
                LabeledContent("Ende durch", value: endReasonText)
                LabeledContent("Bilder", value: "\(report.framesPresented), \(report.frameWidth) × \(report.frameHeight)")
                if report.seconds > 0 {
                    let rate = Double(report.framesPresented) / report.seconds
                    LabeledContent("Bildrate", value: "\(rate.formatted(.number.precision(.fractionLength(1)))) fps (\((rate / 59.94).formatted(.percent.precision(.fractionLength(0)))) von NTSC)")
                }
                if let before = thermalBefore, let after = thermalAfter {
                    LabeledContent("thermalState", value: "\(before.name) → \(after.name)")
                }
                if let check {
                    Label(check.matches ? "Ausgabe = alu.expected" : "Ausgabe weicht ab",
                          systemImage: check.matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(check.matches ? .green : .orange)
                    LabeledContent("Zeilen", value: "\(check.actualLines) von \(check.expectedLines)")
                    if let difference = check.firstDifference {
                        Text(difference).font(.caption.monospaced())
                    }
                }
                if let png = report.lastFramePNG, let image = UIImage(data: png) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel("Letztes Bild des Kerns")
                }
            }
        }
    }
}
