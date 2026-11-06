import Foundation

/// A component whose license notice ships with Arcfold (plan, hard rules;
/// ADR 0005, section 9). project.yml copies each text from its original into
/// `Arcfold.app/Licenses/<folder>/<file>`; the repo keeps no duplicates.
nonisolated struct LicenseComponent: Sendable, Hashable, Identifiable {
    /// The folder below `Licenses` in the app bundle.
    let folder: String
    let file: String
    let name: String
    let version: String?
    /// SPDX identifier.
    let license: String
    /// Where the component comes from, shown above the text.
    let note: String?
    /// Only the leading comment of the file is the license notice.
    let showsLeadingCommentOnly: Bool

    var id: String { folder }

    /// The text from the app bundle, nil if it is missing.
    func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: file, withExtension: nil, subdirectory: "Licenses/\(folder)"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        return showsLeadingCommentOnly ? Self.leadingComment(of: text) : text
    }

    /// The first `/* ... */` block of a C file, without the comment markers.
    static func leadingComment(of source: String) -> String {
        guard let start = source.range(of: "/*"), let end = source.range(of: "*/", range: start.upperBound..<source.endIndex)
        else {
            return source
        }
        var body = source[start.upperBound..<end.lowerBound]
        // Doxygen comments open with "/*!".
        if body.hasPrefix("!") {
            body = body.dropFirst()
        }
        return body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var line = line.drop { $0 == " " || $0 == "\t" }
                if line.hasPrefix("*") {
                    line = line.dropFirst()
                }
                return line.hasPrefix(" ") ? String(line.dropFirst()) : String(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum LicenseCatalog {
    /// Arcfold, the core and the parts of it with their own licenses, and the
    /// libretro API header. M3 adds PPSSPP and MoltenVK.
    static let components: [LicenseComponent] = [
        LicenseComponent(
            folder: "Arcfold", file: "LICENSE", name: "Arcfold", version: nil, license: "GPL-3.0",
            note: nil, showsLeadingCommentOnly: false),
        // The version follows the submodule Cores/mgba; EmbeddedCoreTests checks it.
        LicenseComponent(
            folder: "mGBA", file: "LICENSE", name: "mGBA", version: "0.10.5", license: "MPL-2.0",
            note: String(localized: "Source code: github.com/mgba-emu/mgba, tag 0.10.5",
                         comment: "Where the source of the mGBA core is, on the Licenses screen. Keep the address and tag."),
            showsLeadingCommentOnly: false),
        LicenseComponent(
            folder: "blip_buf", file: "license.txt", name: "blip_buf", version: "1.1.0", license: "LGPL-2.1-or-later",
            note: String(localized: "Part of mGBA. Copyright (C) 2003-2009 Shay Green.",
                         comment: "Origin of the blip_buf library on the Licenses screen."),
            showsLeadingCommentOnly: false),
        LicenseComponent(
            folder: "inih", file: "LICENSE.txt", name: "inih", version: nil, license: "BSD-3-Clause",
            note: String(localized: "Part of mGBA.", comment: "Origin of the inih library on the Licenses screen."),
            showsLeadingCommentOnly: false),
        LicenseComponent(
            folder: "libretro.h", file: "libretro.h", name: "libretro.h", version: nil, license: "MIT",
            note: String(localized: "The libretro API header, from libretro-common.",
                         comment: "Origin of libretro.h on the Licenses screen."),
            showsLeadingCommentOnly: true),
    ]
}
