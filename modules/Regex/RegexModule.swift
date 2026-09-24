import Swiftalk

// `Regex` — regular expressions, swiftalk's second native module (round
// 186; a core type from round 86 until then). The grammar of the literal,
// `/pattern/flags`, stays in the core; its meaning is here: the `Regex`
// type this module exports is what the literal calls. It wraps Swift's
// stdlib Regex, so the syntax is Swift's, and it extends String with the
// members that take one — contains, firstMatch, wholeMatch, matches,
// replacing, split — the core's own String members answering when the
// argument is not a Regex. The CLI preimports it; an embedder puts
// libRegex on the module path and does the same, or lives without
// literals.

/// The value behind a `/re/` (round 86): the pattern, its flags (a subset
/// of `imsx`, kept sorted, applied as an inline `(?flags)` prefix), and
/// the compiled engine.
final class RegexValue: Swiftalk.HostValue {
    let pattern: String
    let flags: String
    let regex: Regex<AnyRegexOutput>
    let type: Swiftalk.Value

    init(pattern: String, flags: String, type: Swiftalk.Value) throws {
        for f in flags where !"imsx".contains(f) {
            throw Swiftalk.Error.syntax("unknown regex flag '\(f)' — i, m, s, x are the flags")
        }
        let sorted = String(flags.sorted())
        self.pattern = pattern
        self.flags = sorted
        self.type = type
        do {
            regex = try Regex(sorted.isEmpty ? pattern : "(?\(sorted))" + pattern)
        } catch {
            throw Swiftalk.Error.syntax("invalid regex /\(pattern)/: \(error)")
        }
    }

    var typeName: String { "Regex" }

    func member(_ name: String, args: [Swiftalk.Value], called: Bool) throws -> Swiftalk.Value? {
        switch (name, called) {
        case ("pattern", false): return .string(pattern)
        case ("flags", false):   return .string(flags)
        default:                 return nil
        }
    }

    func isEqual(to other: any Swiftalk.HostValue) -> Bool {
        guard let o = other as? RegexValue else { return false }
        return o.pattern == pattern && o.flags == flags
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pattern)
        hasher.combine(flags)
    }

    /// `/pattern/flags` — a `/` inside the pattern escaped as `\/`, which
    /// the lexer turns back into `/` (the round-trip law).
    func sourceString(debug: Bool) -> String {
        "/" + pattern.map { $0 == "/" ? "\\/" : String($0) }.joined() + "/" + flags
    }

    /// `case /re/:` matches a String WHOLE (Swift's ~=); a non-String
    /// subject is no match — and, as a binding's source, an error.
    func patternMatch(_ subject: Swiftalk.Value, binding: Bool) throws -> Swiftalk.Value? {
        guard case .string(let s) = subject else {
            if binding { throw Swiftalk.Error.type("a Regex case needs a String subject, not \(subject.typeName)") }
            return nil
        }
        return s.wholeMatch(of: regex).map(matchValue)
    }
}

/// A match is the matched String when the regex has no capture groups,
/// and a tuple when it has: `.0` the whole match, then the groups in
/// order, labeled by name where the group has one, nil where a group did
/// not participate — Swift's own output shape, in swiftalk's tuples.
func matchValue(_ m: Regex<AnyRegexOutput>.Match) -> Swiftalk.Value {
    let elements = Array(m.output)
    if elements.count == 1 {
        return .string(elements[0].substring.map(String.init) ?? "")
    }
    return .tuple(elements.map { e in e.substring.map { .string(String($0)) } ?? .nil },
                  labels: elements.map(\.name))
}

private func regex(_ v: Swiftalk.Value) -> RegexValue? {
    if case .host(let h) = v { return h as? RegexValue }
    return nil
}

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "Regex")
    final class TypeBox { var value: Swiftalk.Value = .nil }
    let box = TypeBox()

    /// `Regex(pattern)`, `Regex(pattern, flags)`, `Regex(r)`; `s.Regex("i")`
    /// by round 47's law; the literal `/pattern/flags` calls this too.
    box.value = m.type("Regex") { args in
        switch args.count {
        case 1:
            if let r = regex(args[0]) { return .host(r) }
            guard case .string(let pattern) = args[0] else {
                throw Swiftalk.Error.type("cannot convert \(args[0].typeName) to Regex")
            }
            return .host(try RegexValue(pattern: pattern, flags: "", type: box.value))
        case 2:
            guard case .string(let pattern) = args[0], case .string(let flags) = args[1] else {
                throw Swiftalk.Error.type("Regex(pattern, flags) takes two Strings")
            }
            return .host(try RegexValue(pattern: pattern, flags: flags, type: box.value))
        default:
            throw Swiftalk.Error.type("Regex(pattern) — or write the literal /pattern/")
        }
    }

    // ---- the String side of the API, Swift's names (round 86) ----
    m.extend("String", "contains") { receiver, args, called in
        guard called, args.count == 1, let r = regex(args[0]), case .string(let s) = receiver else { return nil }
        return .bool(s.contains(r.regex))
    }
    for name in ["firstMatch", "wholeMatch", "matches"] {
        m.extend("String", name) { receiver, args, called in
            guard called, case .string(let s) = receiver else { return nil }
            guard args.count == 1, let r = regex(args[0]) else {
                throw Swiftalk.Error.type(".\(name) takes a Regex: s.\(name)(/re/)")
            }
            switch name {
            case "firstMatch": return s.firstMatch(of: r.regex).map(matchValue) ?? .nil
            case "wholeMatch": return s.wholeMatch(of: r.regex).map(matchValue) ?? .nil
            default:           return .array(s.matches(of: r.regex).map(matchValue))
            }
        }
    }
    /// s.replacing(/re/, "x") / s.replacing(/re/) { m in ... }; the
    /// String-for-String form is the core's.
    m.extend("String", "replacing") { receiver, args, called in
        guard called, case .string(let s) = receiver, args.count == 2, let r = regex(args[0]) else { return nil }
        switch args[1] {
        case .string(let with):
            return .string(s.replacing(r.regex, with: with))
        case .function:
            var out = ""
            var cursor = s.startIndex
            for match in s.matches(of: r.regex) {
                out += s[cursor..<match.range.lowerBound]
                guard case .string(let piece) = try Swiftalk.call(args[1], [matchValue(match)]) else {
                    throw Swiftalk.Error.type("the .replacing Function must return a String")
                }
                out += piece
                cursor = match.range.upperBound
            }
            out += s[cursor...]
            return .string(out)
        default:
            throw Swiftalk.Error.type(".replacing takes what to find (a Regex or a String) and the replacement (a String, or a Function of the match)")
        }
    }
    /// s.split(/re/) — the pieces, empty ones omitted (Swift's default), a [String] (round 177)
    m.extend("String", "split") { receiver, args, called in
        guard called, case .string(let s) = receiver, args.count == 1, let r = regex(args[0]) else { return nil }
        return .array(s.split(separator: r.regex).map { .string(String($0)) },
                      lock: TypeAnnotation("Array", parameters: [TypeAnnotation("String")]))
    }
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
