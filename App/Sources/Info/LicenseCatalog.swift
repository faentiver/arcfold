import Foundation

/// A component whose license notice ships with Arcfold (plan, hard rules;
/// ADR 0005, section 9; ADR 0006). project.yml copies each text from its
/// original into `Arcfold.app/Licenses/<folder>/<file>`; the repo keeps no
/// duplicates.
nonisolated struct LicenseComponent: Sendable, Hashable, Identifiable {
    /// Which part of the file is the notice.
    nonisolated enum Excerpt: Sendable, Hashable {
        /// The whole file.
        case whole
        /// The first `/* ... */` block of a C file, without the comment markers;
        /// a one-line SPDX tag before it is skipped.
        case leadingComment
        /// The lines after the line that starts with `heading`, up to the next
        /// line that starts with `nextHeading`; for files that collect the
        /// notices of several components. A section written as `//`
        /// comments, like that of date, loses the markers.
        case section(heading: String, nextHeading: String)
    }

    /// The folder below `Licenses` in the app bundle.
    let folder: String
    let file: String
    let name: String
    let version: String?
    /// SPDX expression.
    let license: String
    /// Where the component comes from, shown above the text.
    let note: String?
    let excerpt: Excerpt

    /// Names are unique; two components may share a file.
    var id: String { name }

    init(folder: String, file: String, name: String, version: String? = nil, license: String,
         note: String? = nil, excerpt: Excerpt = .whole) {
        self.folder = folder
        self.file = file
        self.name = name
        self.version = version
        self.license = license
        self.note = note
        self.excerpt = excerpt
    }

    /// The notice from the app bundle, nil if the file or the section is missing.
    func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: file, withExtension: nil, subdirectory: "Licenses/\(folder)"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        switch excerpt {
        case .whole:
            return text
        case .leadingComment:
            return Self.leadingComment(of: text)
        case let .section(heading, nextHeading):
            return Self.section(of: text, heading: heading, nextHeading: nextHeading)
        }
    }

    /// The first `/* ... */` block of a C file, without the comment markers.
    /// A block that holds only an SPDX tag, like `/* SPDX-License-Identifier: MIT */`
    /// before the notice of libslirp's files, is skipped.
    static func leadingComment(of source: String) -> String {
        var searchStart = source.startIndex
        var block: Range<String.Index>?
        while let start = source.range(of: "/*", range: searchStart..<source.endIndex),
              let end = source.range(of: "*/", range: start.upperBound..<source.endIndex) {
            let body = source[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("SPDX-License-Identifier:"), !body.contains("\n") {
                searchStart = end.upperBound
                continue
            }
            block = start.upperBound..<end.lowerBound
            break
        }
        guard let block else {
            return source
        }
        var body = source[block]
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

    /// The lines between the line that starts with `heading` and the next line
    /// that starts with `nextHeading`, trimmed; nil if either line is missing.
    /// When every line that is not empty starts with `//`, the markers and one
    /// space after them go.
    static func section(of source: String, heading: String, nextHeading: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(heading) }),
              let end = lines[(start + 1)...].firstIndex(where: { $0.hasPrefix(nextHeading) })
        else {
            return nil
        }
        var body = lines[(start + 1)..<end].map(String.init)
        let written = body.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !written.isEmpty, written.allSatisfy({ $0.hasPrefix("//") }) {
            body = body.map { line in
                guard line.hasPrefix("//") else { return line }
                let rest = line.dropFirst(2)
                return String(rest.hasPrefix(" ") ? rest.dropFirst() : rest)
            }
        }
        return body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum LicenseCatalog {
    /// Arcfold, the cores, every part built into them with its own license, and
    /// the libretro API header. M3 adds PPSSPP and MoltenVK.
    static let components: [LicenseComponent] = [
        // The copyright notice and where the source code is. The source of the
        // cores is there too: their Corresponding Source includes Arcfold's
        // recipes, which change melonDS DS and melonDS (GPL-3.0, sections 5
        // and 6).
        LicenseComponent(
            folder: "Arcfold", file: "LICENSE", name: "Arcfold", license: "GPL-3.0-or-later",
            note: String(localized: "Copyright 2026 Fatih (faentiver). Source code: https://github.com/faentiver/arcfold. It includes the build recipes and scripts in Scripts/ that build the embedded cores from their sources and apply Arcfold's changes to them.",
                         comment: "Copyright notice of Arcfold and where its source code is, on the Licenses screen. Keep the name, the year, the address and the folder name.")),
        // The version follows the submodule Cores/mgba; LicenseCatalogTests checks it.
        LicenseComponent(
            folder: "mGBA", file: "LICENSE", name: "mGBA", version: "0.10.5", license: "MPL-2.0",
            note: String(localized: "Source code: github.com/mgba-emu/mgba, tag 0.10.5",
                         comment: "Where the source of the mGBA core is, on the Licenses screen. Keep the address and tag.")),
        LicenseComponent(
            folder: "blip_buf", file: "license.txt", name: "blip_buf", version: "1.1.0", license: "LGPL-2.1-or-later",
            note: String(localized: "Part of mGBA in version 1.1.0; melonDS brings its own copy of the same library without a version number. Copyright (C) 2003-2009 Shay Green.",
                         comment: "Origin of the blip_buf library on the Licenses screen. Keep the version and the name.")),
        LicenseComponent(
            folder: "inih", file: "LICENSE.txt", name: "inih", license: "BSD-3-Clause",
            note: String(localized: "Part of mGBA.", comment: "Origin of the inih library on the Licenses screen.")),
        LicenseComponent(
            folder: "libretro.h", file: "libretro.h", name: "libretro.h", license: "MIT",
            note: String(localized: "The libretro API header, from libretro-common.",
                         comment: "Origin of libretro.h on the Licenses screen."),
            excerpt: .leadingComment),
        // melonDS DS and what it builds in (ADR 0006). The version follows the
        // submodule Cores/melonds-ds; LicenseCatalogTests checks it. Both
        // notes name Arcfold's changes with their date (GPL-3.0, section 5 a);
        // the recipe Scripts/cores/melondsds.sh makes them.
        LicenseComponent(
            folder: "melonDS-DS", file: "LICENSE", name: "melonDS DS", version: "1.4.0", license: "GPL-3.0-or-later",
            note: String(localized: "Source code: github.com/JesseTG/melonds-ds, tag v1.4.0. Arcfold builds it without JIT. On 7 November 2026 Arcfold changed it so that it builds without libpcap, took out DownloadTmd and CacheTmd, which download and store title metadata in the DSi mode, and removed the DSi's key material from melonDS, which is part of it. The changes are in Scripts/cores/melondsds.sh in Arcfold's source code.",
                         comment: "Where the source of the melonDS DS core is and how Arcfold changed it, on the Licenses screen. Keep the address, the tag, the date, the function names and the file path.")),
        LicenseComponent(
            folder: "melonDS", file: "LICENSE", name: "melonDS", license: "GPL-3.0-or-later",
            note: String(localized: "Part of melonDS DS. Source code: github.com/melonDS-emu/melonDS, commit 906e9eb. It includes SHA-1 in C by Steve Reid, which is in the public domain. On 7 November 2026 Arcfold removed the DSi's key material from it: the AES key of boot2, the key X of modcrypt and of the key slots, the eMMC keys and the key scrambler constant. Arcfold runs only the DS mode, which needs none of them. The change is in Scripts/cores/melondsds.sh in Arcfold's source code.",
                         comment: "Where the source of melonDS is and how Arcfold changed it, on the Licenses screen. Keep the address, the commit, the date and the file path.")),
        LicenseComponent(
            folder: "FreeBIOS", file: "drastic_bios_readme.txt", name: "FreeBIOS", license: "BSD-2-Clause",
            note: String(localized: "Part of melonDS: the replacement for the console's BIOS that lets Arcfold start DS games without BIOS files.",
                         comment: "Origin of FreeBIOS on the Licenses screen.")),
        LicenseComponent(
            folder: "FatFs", file: "LICENSE.txt", name: "FatFs", license: "BSD-1-Clause",
            note: String(localized: "Part of melonDS.", comment: "Origin of a library on the Licenses screen.")),
        LicenseComponent(
            folder: "teakra", file: "LICENSE", name: "teakra", license: "MIT",
            note: String(localized: "Part of melonDS.", comment: "Origin of a library on the Licenses screen.")),
        LicenseComponent(
            folder: "tiny-AES-c", file: "unlicense.txt", name: "Tiny AES in C", license: "Unlicense",
            note: String(localized: "Part of melonDS.", comment: "Origin of a library on the Licenses screen.")),
        LicenseComponent(
            folder: "xxHash", file: "xxhash.h", name: "xxHash", license: "BSD-2-Clause",
            note: String(localized: "Part of melonDS.", comment: "Origin of a library on the Licenses screen."),
            excerpt: .leadingComment),
        LicenseComponent(
            folder: "melonDS-DS-notices", file: "melondsds-LICENSE.txt.in", name: "libretro-common", license: "MIT",
            note: String(localized: "Part of melonDS DS.", comment: "Origin of a library on the Licenses screen."),
            excerpt: .section(heading: "# libretro-common ", nextHeading: "# OpenGL Mathematics (GLM) ")),
        // libslirp: the BSD files of Danny Gasparovski and of later authors
        // under the same terms, the files from 4.4BSD with the terms of the
        // University of California, and the MIT files (ADR 0006, section 3).
        LicenseComponent(
            folder: "libslirp", file: "COPYRIGHT", name: "libslirp", license: "BSD-3-Clause",
            note: String(localized: "Part of melonDS DS. Arcfold switches its network emulation off. Further files of libslirp built into Arcfold are under these terms with these copyright lines: Copyright (c) 2013 Guillaume Subiron, Yann Bordenave, Serigne Modou Wagne; Copyright 2016 Thomas Huth, Red Hat Inc.; Copyright Gavin Shan, IBM Corporation 2016; Copyright (C) 2016-2018 IBM Corp.",
                         comment: "Origin and further copyright holders of libslirp on the Licenses screen. Keep the names and years.")),
        LicenseComponent(
            folder: "libslirp-BSD", file: "tcp_var.h", name: "libslirp, parts from 4.4BSD", license: "BSD-3-Clause",
            note: String(localized: "Files of libslirp from 4.4BSD are under these terms. They name: Copyright (c) 1982, 1986, 1988, 1990, 1992, 1993, 1994 The Regents of the University of California.",
                         comment: "Copyright holder of libslirp's files from 4.4BSD on the Licenses screen. Keep the name and years."),
            excerpt: .leadingComment),
        LicenseComponent(
            folder: "libslirp-MIT", file: "util.h", name: "libslirp, MIT parts", license: "MIT",
            note: String(localized: "Seven of the files of libslirp built into Arcfold are under this license. Besides the copyright lines below, they name: Copyright (c) 2011 AdaCore; Copyright (c) 2012 Klaus Stengel; Copyright (c) 2004 Magnus Damm; Copyright (c) 2004 and 2004-2008 Fabrice Bellard; Copyright (c) 2010-2016 Red Hat, Inc.",
                         comment: "Copyright holders of libslirp's MIT files on the Licenses screen. Keep the names and years."),
            excerpt: .leadingComment),
        LicenseComponent(
            folder: "fmt", file: "LICENSE", name: "{fmt}", license: "MIT",
            note: String(localized: "Part of melonDS DS.", comment: "Origin of a library on the Licenses screen.")),
        LicenseComponent(
            folder: "GLM", file: "copying.txt", name: "OpenGL Mathematics (GLM)", license: "MIT",
            note: String(localized: "Part of melonDS DS.", comment: "Origin of a library on the Licenses screen.")),
        LicenseComponent(
            folder: "pntr", file: "LICENSE.md", name: "pntr", license: "Zlib",
            note: String(localized: "Part of melonDS DS. Of the libraries pntr brings along, Arcfold builds stb_image, stb_image_write, stb_truetype and font8x8 and uses them under their public-domain terms.",
                         comment: "Origin of pntr and the libraries it bundles, on the Licenses screen. Keep the library names.")),
        LicenseComponent(
            folder: "yamc", file: "LICENSE", name: "yamc", license: "MIT",
            note: String(localized: "Part of melonDS DS.", comment: "Origin of a library on the Licenses screen.")),
        LicenseComponent(
            folder: "span-lite", file: "LICENSE.txt", name: "span lite", license: "BSL-1.0",
            note: String(localized: "Part of melonDS DS.", comment: "Origin of a library on the Licenses screen.")),
        // date's own LICENSE.txt is the MIT license without names; the notice
        // with its authors comes from the collected notices of melonDS DS,
        // the same as the head of date.h.
        LicenseComponent(
            folder: "melonDS-DS-notices", file: "melondsds-LICENSE.txt.in", name: "date", license: "MIT",
            note: String(localized: "Part of melonDS DS.", comment: "Origin of a library on the Licenses screen."),
            excerpt: .section(heading: "# date ", nextHeading: "# Dolphin ")),
        LicenseComponent(
            folder: "zlib", file: "LICENSE", name: "zlib", license: "Zlib",
            note: String(localized: "Part of melonDS DS.", comment: "Origin of a library on the Licenses screen.")),
        LicenseComponent(
            folder: "melonDS-DS-notices", file: "melondsds-LICENSE.txt.in", name: "Open Sans", license: "OFL-1.1",
            note: String(localized: "Two fonts of melonDS DS, embedded for its own error screen, which Arcfold never shows.",
                         comment: "Origin of the Open Sans fonts on the Licenses screen."),
            excerpt: .section(heading: "# Open Sans ", nextHeading: "# pcap ")),
    ]
}
