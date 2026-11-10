import SwiftUI

@main
struct ArcfoldApp: App {
    /// One library for every window; the file system is its only source.
    @State private var library = GameLibrary()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = GlassGallery.requestedPage {
                GlassGallery(page: page)
            } else {
                RootView()
                    .environment(library)
            }
            #else
            RootView()
                .environment(library)
            #endif
        }
    }
}
