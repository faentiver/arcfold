import SwiftUI

/// The license notices of Arcfold and every component it ships.
struct LicensesView: View {
    var body: some View {
        List(LicenseCatalog.components) { component in
            NavigationLink(value: component) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: component.version.map { "\(component.name) \($0)" } ?? component.name)
                    Text(verbatim: component.license)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text("Licenses", comment: "Title of the screen with the license notices."))
        .navigationDestination(for: LicenseComponent.self) { component in
            LicenseTextView(component: component)
        }
    }
}

/// The text of one license, split into paragraphs so that long texts like the
/// GPL lay out lazily.
struct LicenseTextView: View {
    let component: LicenseComponent
    @State private var paragraphs: [String]?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let note = component.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let paragraphs {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(verbatim: paragraphs[index])
                    }
                } else {
                    ProgressView()
                }
            }
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(verbatim: component.name))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            paragraphs = await Self.paragraphs(of: component)
        }
    }

    @concurrent
    private static func paragraphs(of component: LicenseComponent) async -> [String] {
        guard let text = component.text() else {
            return [String(localized: "The license text is missing from this build.",
                           comment: "Shown instead of a license text that is not in the app bundle.")]
        }
        return text
            .replacing("\r\n", with: "\n")
            .split(separator: "\n\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}
