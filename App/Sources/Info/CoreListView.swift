import LibretroKit
import SwiftUI

/// The cores embedded in this build, loaded through LibretroKit. Reached from
/// the info menu of the library.
struct CoreListView: View {
    @State private var state = CoreCatalog.State.loading

    var body: some View {
        content
            .navigationTitle(Text("Cores", comment: "Navigation title of the list of libretro cores embedded in the app."))
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
    NavigationStack {
        CoreListView()
    }
}
