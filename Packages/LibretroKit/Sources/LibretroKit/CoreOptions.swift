internal import CLibretro
import Darwin

/// The core options of one session, in the legacy interface
/// (`RETRO_ENVIRONMENT_SET_VARIABLES` and `GET_VARIABLE`, ADR 0005).
///
/// A core declares its options with a description and the allowed values,
/// `"Description; first|second|…"`; the first value is the default. mGBA frees
/// those strings right after the call, so keys and defaults are copied at once.
/// `GET_VARIABLE` answers with C strings that this object owns: the same key
/// always gets the same address, valid for the whole session, because cores
/// keep the pointers. Emulation thread only.
final class CoreOptions {
    /// Values from `SessionConfiguration.coreOptions`; they replace the defaults.
    private let overrides: [String: String]
    /// The defaults the core declared.
    private var defaults: [String: String] = [:]
    /// The C string handed out for each key.
    private var answers: [String: UnsafeMutablePointer<CChar>] = [:]
    /// Every C string ever handed out; freed with this object, never earlier.
    private var allocations: [UnsafeMutablePointer<CChar>] = []

    init(overrides: [String: String]) {
        self.overrides = overrides
    }

    deinit {
        for string in allocations {
            free(string)
        }
    }

    /// The keys the core declared, in no particular order.
    var declaredKeys: Dictionary<String, String>.Keys {
        defaults.keys
    }

    /// The default the core declared for `key`.
    func declaredDefault(for key: String) -> String? {
        defaults[key]
    }

    /// Copies keys and defaults from the `{ NULL, NULL }`-terminated array of
    /// `RETRO_ENVIRONMENT_SET_VARIABLES`. Returns the number of options.
    @discardableResult
    func declare(_ variables: UnsafePointer<retro_variable>) -> Int {
        var count = 0
        var cursor = variables
        while let key = cursor.pointee.key {
            let name = String(cString: key)
            let declaration = cursor.pointee.value.map { String(cString: $0) } ?? ""
            let value = Self.defaultValue(of: declaration)
            if defaults[name] != value {
                defaults[name] = value
                // A changed default needs a new string. The old one stays
                // allocated, because the core may still hold its address.
                if overrides[name] == nil {
                    answers[name] = nil
                }
            }
            count += 1
            cursor += 1
        }
        return count
    }

    /// The answer to `RETRO_ENVIRONMENT_GET_VARIABLE`: the configured value,
    /// else the declared default; nil for a key that is neither.
    func value(for key: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
        let name = String(cString: key)
        if let answer = answers[name] {
            return UnsafePointer(answer)
        }
        guard let value = overrides[name] ?? defaults[name], let answer = strdup(value) else {
            return nil
        }
        allocations.append(answer)
        answers[name] = answer
        return UnsafePointer(answer)
    }

    /// The first value of `"Description; first|second|…"`. A declaration
    /// without description is taken as the value list itself.
    static func defaultValue(of declaration: String) -> String {
        let values = declaration.firstIndex(of: ";").map { declaration[declaration.index(after: $0)...] }
            ?? declaration[...]
        let first = values.drop { $0 == " " }.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first
        return first.map(String.init) ?? ""
    }
}
