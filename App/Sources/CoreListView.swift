import LibretroKit
import SwiftUI

/// The cores embedded in this build, loaded through LibretroKit. Proof of the
/// loading path for M0, not the app's interface.
struct CoreListView: View {
    @State private var state = CoreCatalog.State.loading

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cores")
        }
        .task {
            state = await CoreCatalog.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
        case .loaded(let cores):
            List(cores) { core in
                LabeledContent(core.name, value: core.version)
            }
        case .noCores:
            ContentUnavailableView(
                "No Cores",
                systemImage: "shippingbox",
                description: Text("This build contains no libretro cores.")
            )
        case .failed(let error):
            ContentUnavailableView(
                "Core Failed to Load",
                systemImage: "exclamationmark.triangle",
                description: Text(verbatim: error.description)
            )
        }
    }
}

#Preview {
    CoreListView()
}
