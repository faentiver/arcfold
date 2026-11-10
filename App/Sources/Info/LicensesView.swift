import SwiftUI

/// The license notices of Arcfold and every component it ships: a list that
/// opens each text. While a fold divides the window from top to bottom (the
/// Duo held like a book), the list takes the first page and the chosen text
/// the second, the way the system arranges Settings there (`ArrangementView`,
/// iOS 27.1); nothing lies on the fold.
struct LicensesView: View {
    @State private var isDivided = false
    /// The component whose text shows beside the list; the first one until
    /// another is chosen.
    @State private var selection: LicenseComponent.ID?

    var body: some View {
        content
            .onFoldDivisionChange { isDivided = $0 }
            .navigationTitle(Text("Licenses", comment: "Title of the screen with the license notices."))
            .navigationDestination(for: LicenseComponent.self) { component in
                LicenseTextView(component: component)
            }
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 27.1, *), isDivided {
            let components = LicenseCatalog.components
            let shown = components.first { $0.id == selection } ?? components[0]
            ArrangementView {
                List(components, selection: Binding(get: { shown.id }, set: { selection = $0 ?? selection })) { component in
                    // One element per row, as a navigation link is one.
                    LicenseRow(component: component)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                }
                .contentMargins(.trailing, FoldDivision.pageMargin, for: .scrollContent)
            } secondary: {
                LicenseText(component: shown, isBesideTheList: true)
                    .id(shown.id)
            }
        } else {
            List(LicenseCatalog.components) { component in
                NavigationLink(value: component) {
                    LicenseRow(component: component)
                }
            }
        }
    }
}

/// One component in the list: its name with its version, and its license.
private struct LicenseRow: View {
    let component: LicenseComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: component.version.map { "\(component.name) \($0)" } ?? component.name)
            Text(verbatim: component.license)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// The text of one license as a screen of its own, under the name of the
/// component.
struct LicenseTextView: View {
    let component: LicenseComponent

    var body: some View {
        LicenseText(component: component, isBesideTheList: false)
            // Folded like a book while it shows: beside the fold, not across it.
            .onFirstFoldPage()
            .navigationTitle(Text(verbatim: component.name))
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The text of one license, split into paragraphs so that long texts like the
/// GPL lay out lazily. Beside the list, on the second page at a fold, it
/// begins with the name of the component, because no navigation bar names it
/// there, and the system's margin behind the fold, like the second page of
/// the library.
private struct LicenseText: View {
    let component: LicenseComponent
    let isBesideTheList: Bool
    @State private var paragraphs: [String]?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if isBesideTheList {
                    Text(verbatim: component.name)
                        .font(.headline)
                }
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
            .padding([.vertical, .trailing])
            .padding(.leading, isBesideTheList ? FoldDivision.pageMargin : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
