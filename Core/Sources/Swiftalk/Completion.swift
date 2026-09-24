/// Completion (round 164): what the REPL's Tab offers. The engine lives
/// in the core so an embedder's editor can use it too — `Interpreter.
/// complete(text)` takes the text up to the cursor and answers with
/// where the word being completed starts and what it could become.
///
/// Three situations. A word after a dot completes a *member*: the
/// receiver — a chain of names, `a.b.c` — is evaluated (reads only;
/// no call or subscript is ever completed through), and its value says
/// what it has: a struct's properties, computed properties, and
/// methods; an enum's cases and methods; a type's statics; and for a
/// builtin value, the table below. A dot with nothing before it offers
/// the format words and Result's cases. Anything else completes a
/// *name*: everything in scope, the builtins, the keywords — and at a
/// line's start, the REPL's `:` commands.
enum Completion {
    /// What every value answers to.
    static let common = ["Type", "String", "description", "debugDescription"]

    /// The builtin types' members, by type name — curated from the type
    /// pages in documents/, which are derived from the evaluator; a test asks
    /// the evaluator that each name is still one it knows.
    static let members: [String: [String]] = [
        "Nil": [],
        "Bool": ["not", "and", "or", "xor"],
        "Int": ["Double", "Byte", "bit", "bits", "bitAnd", "bitOr", "bitXor", "bitNot", "shifted",
                "leadingZeroBitCount", "trailingZeroBitCount", "nonzeroBitCount"],
        "Double": ["Int", "Date"],
        "String": ["Int", "Double", "Bool", "Data", "SION", "Array", "Set", "Sequence", "Tuple",
                   "count", "first", "contains", "map", "filter", "reduce", "forEach", "sorted", "reversed",
                   "joined", "split", "enumerated", "prefix", "suffix", "dropFirst", "dropLast", "min", "max",
                   "escaped", "unescaped", "normalized", "isNormalized", "unicodeScalars", "utf8", "utf32",
                   "replacing", "firstMatch", "wholeMatch", "matches"],
        "Array": ["Set", "Sequence", "Tuple", "Data", "count", "first", "contains", "append",
                  "map", "filter", "reduce", "forEach", "sorted", "reversed", "joined", "split", "enumerated",
                  "prefix", "suffix", "dropFirst", "dropLast", "min", "max"],
        "Dictionary": ["Array", "Sequence", "Tuple", "count", "first", "has", "keys", "values",
                       "merge", "merging", "subtract", "map", "filter", "reduce", "forEach", "enumerated",
                       "prefix", "suffix", "dropFirst", "dropLast", "min", "max"],
        "Set": ["Array", "Sequence", "count", "first", "contains", "insert", "remove", "merge", "subtract",
                "subtracting", "union", "intersection", "symmetricDifference",
                "isSubset", "isSuperset", "isStrictSubset", "isStrictSuperset", "isDisjoint",
                "map", "filter", "reduce", "forEach", "sorted", "enumerated", "min", "max"],
        "Range": ["Array", "Set", "Sequence", "count", "contains", "map", "filter", "reduce", "forEach",
                  "sorted", "reversed", "split", "enumerated", "prefix", "suffix", "dropFirst", "dropLast",
                  "first", "min", "max"],
        "Function": ["name", "Sequence", "Task"],
        "Sequence": ["Array", "Set", "count", "contains", "map", "filter", "reduce", "forEach", "sorted",
                     "reversed", "joined", "split", "enumerated", "prefix", "suffix", "dropFirst", "dropLast",
                     "first", "min", "max"],
        "Data": ["Array", "Sequence", "count", "first", "contains", "map", "filter", "reduce", "forEach",
                 "sorted", "reversed", "enumerated", "prefix", "suffix", "dropFirst", "dropLast", "min", "max"],
        "Date": ["Double"],
        "Task": [],
        "Tuple": ["Array", "Tuple", "count", "first", "map", "filter", "reduce", "forEach", "enumerated"],
        "Byte": ["Int", "bitAnd", "bitOr", "bitXor", "bitNot", "shifted"],
        "Result": ["success", "failure", "then", "catch"],
    ]

    /// The builtin types' statics — `Int.max`, `Double.sqrt`, … — by type name.
    static let statics: [String: [String]] = [
        "Int": ["min", "max", "bitWidth", "isSigned", "zero", "random"],
        "Byte": ["min", "max", "bitWidth", "isSigned", "zero"],
        "Double": ["pi", "e", "tau", "infinity", "nan", "zero", "ln2", "ln10", "log2e", "log10e", "sqrt2", "sqrtHalf",
                   "greatestFiniteMagnitude", "leastNonzeroMagnitude", "leastNormalMagnitude", "ulpOfOne", "radix",
                   "significandBitCount", "exponentBitCount", "random",
                   "abs", "sign", "floor", "ceil", "round", "trunc", "rint", "nearbyint", "fmod", "remainder", "remquo", "modf",
                   "sqrt", "cbrt", "pow", "hypot", "exp", "exp2", "expm1", "log", "log2", "log10", "log1p", "logb", "ilogb",
                   "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
                   "erf", "erfc", "gamma", "lgamma", "tgamma", "j0", "j1", "jn", "y0", "y1", "yn",
                   "fma", "fmax", "fmin", "fdim", "copysign", "nextafter", "frexp", "ldexp", "scalbn",
                   "isFinite", "isInfinite", "isNaN", "isNormal", "isSubnormal", "isZero"],
        "String": ["fromCodePoint"],
        "Data": ["random"],
        "Sequence": ["zip"],                                     // round 185
        "Task": ["sleep"],
        "Result": ["success", "failure"],
    ]

    /// What every type object answers to.
    static let typeCommon = ["name", "conforms", "Type", "String"]

    /// After a dot with nothing before it: `.pretty`, `.hex`, `.success(v)`, `.Date(0.0)`, …
    static let leadingDot = ["pretty", "sign", "canonical", "quoted", "sion", "json", "propertyList",
                             "hex", "oct", "bin", "utf8", "success", "failure", "Date", "Data", "todo"]

    /// `[1, 2]` / `["a": 1]` ending at `closingAt`, as text — when it is a
    /// literal of literals: any `(` inside could be a call, and a call is
    /// never run for completion.
    static func bracketedLiteral(_ chars: [Character], closingAt end: Int) -> String? {
        var depth = 0
        var i = end
        while i >= 0 {
            if chars[i] == "]" { depth += 1 }
            if chars[i] == "[" { depth -= 1; if depth == 0 { break } }
            i -= 1
        }
        guard i >= 0 else { return nil }
        let text = String(chars[i...end])
        return text.contains("(") ? nil : text
    }

    /// `"…"` ending at `closingAt`, as text — without interpolation.
    static func stringLiteral(_ chars: [Character], closingAt end: Int) -> String? {
        var i = end - 1
        while i >= 0 {
            if chars[i] == "\"" && (i == 0 || chars[i - 1] != "\\") { break }
            i -= 1
        }
        guard i >= 0 else { return nil }
        let text = String(chars[i...end])
        return text.contains("\\(") ? nil : text
    }

    static func isIdentifier(_ c: Character) -> Bool {
        c == "_" || c.isLetter || c.isNumber
    }

    /// The longest prefix every candidate shares — what Tab inserts
    /// when there are several.
    static func commonPrefix(_ candidates: [String]) -> String {
        guard var prefix = candidates.first else { return "" }
        for candidate in candidates.dropFirst() {
            while !candidate.hasPrefix(prefix) { prefix.removeLast() }
            if prefix.isEmpty { break }
        }
        return prefix
    }
}

extension Swiftalk.Interpreter {
    /// Completion for `text`, the line up to the cursor (round 164):
    /// the Character offset where the word being completed begins, and
    /// the candidates, sorted and unique, each starting with that word.
    public func complete(_ text: String) -> (start: Int, candidates: [String]) {
        let chars = Array(text)
        var start = chars.count
        while start > 0, Completion.isIdentifier(chars[start - 1]) { start -= 1 }
        let word = String(chars[start...])
        func done(_ names: [String], from: Int = start) -> (Int, [String]) {
            (from, Array(Set(names.filter { $0.hasPrefix(word) })).sorted())
        }
        // `:h`, `:r`, `:d` — a REPL command at the line's start; a colon
        // anywhere else (a ternary's, a label's) offers nothing
        if start > 0, chars[start - 1] == ":" {
            guard chars[..<(start - 1)].allSatisfy({ $0 == " " || $0 == "\t" }) else { return (start, []) }
            return (start - 1, [":d", ":h", ":r"].filter { $0.hasPrefix(":" + word) })
        }
        if start > 0, chars[start - 1] == "." {
            // the receiver: a chain of names before the dot, nothing else
            var chain: [String] = []
            var end = start - 1
            while true {
                var begin = end
                while begin > 0, Completion.isIdentifier(chars[begin - 1]) { begin -= 1 }
                guard begin < end else { break }
                chain.insert(String(chars[begin..<end]), at: 0)
                guard begin > 0, chars[begin - 1] == "." else { break }
                end = begin - 1
            }
            let receiver: String?
            if !chain.isEmpty {
                receiver = chain.joined(separator: ".")
            } else {
                // no name before the dot: a literal, or the dot leads
                switch chars.indices.contains(start - 2) ? chars[start - 2] : nil {
                case nil, " ", "\t", "(", ",", "[", "=", ":", "?", "{", "\n":
                    return done(Completion.leadingDot)
                case "]":
                    receiver = Completion.bracketedLiteral(chars, closingAt: start - 2)
                case "\"":
                    receiver = Completion.stringLiteral(chars, closingAt: start - 2)
                default:
                    return (start, [])       // `)` and the rest: an expression is not evaluated for completion
                }
            }
            guard let receiver, let value = try? eval(receiver) else { return (start, []) }
            return done(memberNames(of: value))
        }
        var names = environment.names() + keywords
        names.removeAll { $0.hasPrefix("@") || $0.hasPrefix("$") }
        return done(names)
    }

    /// What a value has, for completion after its dot.
    func memberNames(of value: Value) -> [String] {
        switch value {
        case .function(let f):
            switch f.role {
            case .type(let name), .protocol(let name):
                return (Completion.statics[name] ?? []) + Completion.typeCommon + extensionMembers(of: name, statics: true)
            case .structType(let st):
                return Array(st.statics.keys) + Array(st.staticGetters.keys) + Array(st.staticThunks.keys) + Completion.typeCommon
            case .enumType(let et):
                return et.caseOrder + Array(et.statics.keys) + Array(et.staticGetters.keys) + Array(et.staticThunks.keys) + Completion.typeCommon
            case .actorType(let at):
                return Array(at.methods.keys) + Completion.typeCommon
            case .plain, .todo, .operator:
                return Completion.members["Function"]! + Completion.common
            }
        case .structValue(let sv):
            return sv.type.propertyOrder + Array(sv.type.computed.keys) + Array(sv.type.methods.keys) + Completion.common
        case .enumCase(let ev):
            let own = ev.type === Builtins.resultType ? Completion.members["Result"]! : ev.type.caseOrder
            return own + Array(ev.type.methods.keys) + Completion.common
        default:
            let name = value.typeName
            return (Completion.members[name] ?? []) + Completion.common + extensionMembers(of: name, statics: false)
        }
    }

    /// `extension Int { … }` members, kept as `@ext:Int:name` bindings
    /// (`get:` for computed, `static:` for statics) in the root scope.
    private func extensionMembers(of typeName: String, statics: Bool) -> [String] {
        let prefix = "@ext:\(typeName):"
        return environment.names().compactMap { binding -> String? in
            guard binding.hasPrefix(prefix) else { return nil }
            var rest = String(binding.dropFirst(prefix.count))
            let isStatic = rest.hasPrefix("static:")
            guard isStatic == statics else { return nil }
            if isStatic { rest = String(rest.dropFirst("static:".count)) }
            if rest.hasPrefix("get:") { rest = String(rest.dropFirst("get:".count)) }
            return rest
        }
    }
}
