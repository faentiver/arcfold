import SwiftUI

/// Spike for ADR 0001: runs the PPSSPP libretro core in a minimal host and
/// saves captured frames. Launch arguments (all optional):
///   -backend gles|vulkan|software   graphics path, default gles
///   -frames N                        emulated frames to run, default 600
///   -scale N                         PPSSPP render scale, default 1
///   -capture 60,300                  emulated frames to save besides the last one
///   -waitForGPU YES                  wait for the GPU after every frame
///   -cycles N                        run the whole core lifecycle N times
///   -dlclose YES                     dlclose the core after every cycle
///   -exitWhenDone YES                quit after the run, for scripted runs
@main
struct PSPGPUSpikeApp: App {
    @State private var model = SpikeModel()

    var body: some Scene {
        WindowGroup {
            SpikeView(model: model)
                .task { model.startIfNeeded() }
        }
    }
}

struct SpikeView: View {
    let model: SpikeModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = model.lastImage {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                    }
                    Text(model.report)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
