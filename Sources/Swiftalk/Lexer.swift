extension Swiftalk {
    /// Errors thrown by `eval()` and its stages. swiftalk-the-language is
    /// Result-first (Design.md §8); at the Swift implementation layer we
    /// use `throws`, which the embedding API will surface as a `Result`.
    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case syntax(String)
        case type(String)
        case overflow(String)
        case zeroDivision
        case unknownMember(String)

        public var description: String {
            switch self {
            case .syntax(let m):        return "syntax error: \(m)"
            case .type(let m):          return "type error: \(m)"
            case .overflow(let m):      return "overflow: \(m)"
            case .zeroDivision:         return "division by zero"
            case .unknownMember(let m): return "unknown member: \(m)"
            }
        }
    }
}

typealias SwiftalkError = Swiftalk.Error

enum Token: Equatable {
    case int(Int64)
    case double(Double)
    case string(String)
    case interpolated([StringSegment])   // "a\(expr)b" (§2.5, Swift-style)
    case identifier(String)   // also keywords (true/false/nil/let/var/in) and $ / $0 / $1 ...
    case punct(Character)     // [ ] ( ) { } : , . + - * / = ? ;
    case op(String)           // == != < <= > >=
    case regex(pattern: String, flags: String)   // /pattern/flags (round 86)
    case newline              // statement separator (suppressed inside [ and ()
}

/// One piece of an interpolated string literal: literal text, or the
/// tokens of an embedded `\(...)` expression (lexed here, parsed by a
/// sub-parser).
enum StringSegment: Equatable {
    case literal(String)
    case interpolation([Token])
}

struct Lexer {
    private let scalars: [Unicode.Scalar]
    private var pos = 0

    init(_ source: String) {
        self.scalars = Array(source.unicodeScalars)
    }

    private var peek: Unicode.Scalar? { pos < scalars.count ? scalars[pos] : nil }
    private mutating func advance() -> Unicode.Scalar? {
        guard pos < scalars.count else { return nil }
        defer { pos += 1 }
        return scalars[pos]
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        // Newlines separate statements. Inside [ and ( they are suppressed
        // (collection literals and call arguments span lines freely), but
        // inside { } they matter — a function body is a statement list.
        var brackets: [Unicode.Scalar] = []
        var suppressNewlines: Bool {
            brackets.last == "[" || brackets.last == "("
        }
        while let c = peek {
            // A leading binary operator continues the previous line
            // (round 96, Swift's rule): an operator at a line's start
            // with whitespace after it is infix — the newline before it
            // goes; `-x` / `!x` with none is a prefix, a new statement.
            if tokens.count >= 2, tokens[tokens.count - 2] == .newline,
               Lexer.leadsContinuation(tokens.last), c == " " || c == "\t" || c == "\n" {
                tokens.remove(at: tokens.count - 2)
            }
            switch c {
            case " ", "\t", "\r":
                pos += 1
            case "\n":
                pos += 1
                if !suppressNewlines, tokens.last != nil, tokens.last != .newline,
                   !Lexer.continuesLine(after: tokens.last) {
                    tokens.append(.newline)
                }
            case "/":
                // comment, a regex literal, or the division operator
                if pos + 1 < scalars.count, scalars[pos + 1] == "/" {
                    while let c = peek, c != "\n" { pos += 1 }
                } else if pos + 1 < scalars.count, scalars[pos + 1] == "*" {
                    try skipBlockComment()
                } else if Lexer.regexMayStart(after: tokens.last) {
                    tokens.append(try lexRegex())
                } else if pos + 1 < scalars.count, scalars[pos + 1] == "=" {
                    pos += 2
                    tokens.append(.op("/="))                     // round 102
                } else {
                    pos += 1
                    tokens.append(.punct("/"))
                }
            case "[", "(", "{":
                brackets.append(c)
                pos += 1
                tokens.append(.punct(Character(c)))
            case "]", ")", "}":
                if !brackets.isEmpty { brackets.removeLast() }
                pos += 1
                tokens.append(.punct(Character(c)))
            case ":", ",", "+", "-", "*", "%", ";":
                // += -= *= %= (round 102): compound assignment
                if "+-*%".contains(Character(c)), pos + 1 < scalars.count, scalars[pos + 1] == "=" {
                    pos += 2
                    tokens.append(.op(String(c) + "="))
                } else {
                    pos += 1
                    tokens.append(.punct(Character(c)))
                }
            case "?":
                // Disambiguation (round 51): `??` coalesces; unspaced
                // `?.` chains; unspaced `?` is the postfix propagator;
                // spaced `?` is the ternary.
                let unspaced = pos > 0 && !" \t\n\r".unicodeScalars.contains(scalars[pos - 1])
                pos += 1
                if peek == "?" {
                    pos += 1
                    tokens.append(.op("??"))
                } else if unspaced, peek == "." {
                    pos += 1
                    tokens.append(.op("?."))
                } else if unspaced {
                    tokens.append(.op("?"))
                } else {
                    tokens.append(.punct("?"))
                }
            case "&", "|":
                // `&&` / `||` (round 69). A lone `&` or `|` is nothing yet
                // — bitwise operators are undecided.
                pos += 1
                guard peek == c else {
                    throw SwiftalkError.syntax("unexpected '\(c)' — did you mean '\(c)\(c)'?")
                }
                pos += 1
                tokens.append(.op(String(c) + String(c)))
            case "=", "!", "<", ">":
                pos += 1
                if peek == "=" {
                    pos += 1
                    tokens.append(.op(String(c) + "="))
                } else if c == "=" {
                    tokens.append(.punct("="))
                } else if c == "<" || c == ">" {
                    tokens.append(.op(String(c)))
                } else {
                    tokens.append(.op("!"))   // postfix force-unwrap (round 51)
                }
            case "$":
                pos += 1
                var name = "$"
                while let d = peek, ("0"..."9").contains(d) {
                    name.unicodeScalars.append(d)
                    pos += 1
                }
                tokens.append(.identifier(name))
            case ".":
                // `...` / `..<` are range operators; a single `.` is member
                // access. (A leading `.5` float is not swiftalk — Swift
                // also requires `0.5`.)
                if pos + 1 < scalars.count, scalars[pos + 1] == "." {
                    guard pos + 2 < scalars.count,
                          scalars[pos + 2] == "." || scalars[pos + 2] == "<" else {
                        throw SwiftalkError.syntax("'..' is not an operator")
                    }
                    tokens.append(.op(scalars[pos + 2] == "." ? "..." : "..<"))
                    pos += 3
                } else {
                    pos += 1
                    tokens.append(.punct("."))
                }
            case "\"":
                tokens.append(try startsTripleQuote() ? lexMultilineString(hashes: 0)
                                                     : lexStringToken(hashes: 0))
            case "#":
                // Raw strings (round 94): #"..."# / #"""..."""# — a `\` or a
                // `"` counts only when followed by as many `#`s.
                var hashes = 0
                while peek == "#" { hashes += 1; pos += 1 }
                guard peek == "\"" else {
                    throw SwiftalkError.syntax("unexpected character '#'")
                }
                tokens.append(try startsTripleQuote() ? lexMultilineString(hashes: hashes)
                                                     : lexStringToken(hashes: hashes))
            case "0"..."9":
                // After a `.` the digits are a tuple index (round 70):
                // `t.0.1` is two member accesses, not `t` then `0.1`.
                tokens.append(try lexNumber(memberIndex: tokens.last == .punct(".")))
            case let c where c.properties.isAlphabetic || c == "_":
                tokens.append(.identifier(lexIdentifier()))
            default:
                throw SwiftalkError.syntax("unexpected character '\(c)'")
            }
        }
        return tokens
    }

    /// A trailing binary operator continues the line (round 95): the
    /// newline after `+ - * / % =`, a comparison, `&& || ??` is not a
    /// separator. Not after postfix `!`/`?`, and not after `...`/`..<`
    /// — `0...` at a line's end is the unbounded range (round 88).
    static func continuesLine(after last: Token?) -> Bool {
        switch last {
        case .punct(let p)?:
            return "+-*/%=".contains(p)
        case .op(let o)?:
            return ["==", "!=", "<", "<=", ">", ">=", "&&", "||", "??",
                    "+=", "-=", "*=", "/=", "%="].contains(o)
        default:
            return false
        }
    }

    /// The operators that continue the previous line when they lead a
    /// line with whitespace after them (round 96): the trailing set,
    /// plus the spaced ternary's `?` and `:`. Not `.` — `.x = 1` at a
    /// line's start is implicit self (round 49).
    static func leadsContinuation(_ token: Token?) -> Bool {
        if continuesLine(after: token) { return true }
        if case .punct(let p)? = token { return p == "?" || p == ":" }
        return false
    }

    /// JavaScript's rule (round 86): `/` starts a regex literal where an
    /// operand cannot end — at a statement's start, after `(` `[` `{`
    /// `,` `:` `=` `?`, after an operator, after a keyword (`return
    /// /re/`, `case /re/:`, `where /re/`). After a value, a name, or a
    /// closing bracket it is division. (`//` is a comment, so the empty
    /// regex is spelled `Regex("")`.)
    static func regexMayStart(after last: Token?) -> Bool {
        switch last {
        case nil, .newline?, .op?:
            return true
        case .punct(let p)?:
            return p != ")" && p != "]" && p != "}"
        case .identifier(let name)?:
            return (keywords.contains(name) || name == "where")
                && name != "true" && name != "false" && name != "nil"
        case .regex?:
            return false
        case .int?, .double?, .string?, .interpolated?:
            return false
        }
    }

    /// `/pattern/flags`: a backslash keeps the next scalar verbatim —
    /// the engine sees the escape — except `\/`, which is a `/` in the
    /// pattern. Flags are the letters that follow the closing `/`.
    private mutating func lexRegex() throws -> Token {
        pos += 1  // the opening /
        var pattern = ""
        while true {
            guard let c = advance() else {
                throw SwiftalkError.syntax("unterminated regex literal")
            }
            if c == "\n" { throw SwiftalkError.syntax("unterminated regex literal") }
            if c == "/" { break }
            if c == "\\" {
                guard let next = advance() else {
                    throw SwiftalkError.syntax("unterminated regex literal")
                }
                if next == "/" { pattern.unicodeScalars.append("/") }
                else { pattern.unicodeScalars.append(c); pattern.unicodeScalars.append(next) }
                continue
            }
            pattern.unicodeScalars.append(c)
        }
        var flags = ""
        while let c = peek, ("a"..."z").contains(c) {
            flags.unicodeScalars.append(c)
            pos += 1
        }
        return .regex(pattern: pattern, flags: flags)
    }

    private mutating func skipBlockComment() throws {
        pos += 2  // consume "/*"
        var depth = 1
        while depth > 0 {
            guard pos < scalars.count else {
                throw SwiftalkError.syntax("unterminated block comment")
            }
            if scalars[pos] == "*", pos + 1 < scalars.count, scalars[pos + 1] == "/" {
                depth -= 1; pos += 2
            } else if scalars[pos] == "/", pos + 1 < scalars.count, scalars[pos + 1] == "*" {
                depth += 1; pos += 2
            } else {
                pos += 1
            }
        }
    }

    private mutating func lexIdentifier() -> String {
        var name = ""
        while let c = peek, c.properties.isAlphabetic || c == "_" || ("0"..."9").contains(c) {
            name.unicodeScalars.append(c)
            pos += 1
        }
        return name
    }

    /// Lexes a string literal; `\(...)` makes it an interpolated token
    /// whose expression parts are captured as sub-token streams.
    private func startsTripleQuote() -> Bool {
        pos + 2 < scalars.count && scalars[pos] == "\"" && scalars[pos + 1] == "\"" && scalars[pos + 2] == "\""
    }

    /// `hashes` `#`s follow the current position (0 always does).
    private func hashesFollow(_ hashes: Int) -> Bool {
        guard hashes > 0 else { return true }
        guard pos + hashes <= scalars.count else { return false }
        return scalars[pos..<(pos + hashes)].allSatisfy { $0 == "#" }
    }

    /// A single-line literal, `"..."` or `#"..."#`.
    private mutating func lexStringToken(hashes: Int) throws -> Token {
        pos += 1  // consume opening quote
        return try lexStringBody(hashes: hashes, terminated: true)
    }

    /// `"""` (round 94, Swift's rules): the content starts on the line
    /// after the opening delimiter and ends on the line before the
    /// closing one; the closing delimiter's indentation is stripped
    /// from every line (a line with less is an error unless blank);
    /// a `\` at a line's end joins it to the next. Escapes and
    /// interpolation as in a single-line literal; `"` needs no escape.
    private mutating func lexMultilineString(hashes: Int) throws -> Token {
        pos += 3  // the opening """
        while let c = peek, c == " " || c == "\t" { pos += 1 }
        guard peek != nil else {
            // the REPL's case: the opening line alone — more lines wanted
            throw SwiftalkError.syntax("unterminated multi-line string literal — close it with \"\"\" on its own line")
        }
        guard peek == "\n" else {
            throw SwiftalkError.syntax("a multi-line string's content starts on the line after the opening \"\"\"")
        }
        let openingNewline = pos
        pos += 1
        let contentStart = pos
        // find the closing delimiter: a newline, optional indentation, """ and the #s
        var j = openingNewline
        var found: (newline: Int, lineStart: Int, delimiter: Int)? = nil
        while j < scalars.count {
            if scalars[j] == "\n" {
                var m = j + 1
                while m < scalars.count, scalars[m] == " " || scalars[m] == "\t" { m += 1 }
                if m + 2 < scalars.count, scalars[m] == "\"", scalars[m + 1] == "\"", scalars[m + 2] == "\"",
                   (hashes == 0 || (m + 3 + hashes <= scalars.count
                                    && scalars[(m + 3)..<(m + 3 + hashes)].allSatisfy { $0 == "#" })) {
                    found = (j, j + 1, m)
                    break
                }
            }
            j += 1
        }
        guard let (newline, lineStart, delimiter) = found else {
            throw SwiftalkError.syntax("unterminated multi-line string literal — close it with \"\"\" on its own line")
        }
        let indent = Array(scalars[lineStart..<delimiter])
        let content = newline > openingNewline ? Array(scalars[contentStart..<newline]) : []
        // de-indent line by line
        var lines: [[Unicode.Scalar]] = [[]]
        for c in content {
            if c == "\n" { lines.append([]) } else { lines[lines.count - 1].append(c) }
        }
        var body = ""
        for (n, line) in lines.enumerated() {
            if n > 0 { body.append("\n") }
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) && line.count <= indent.count { continue }
            guard line.starts(with: indent) else {
                throw SwiftalkError.syntax(
                    "line \(n + 1) of the multi-line string is indented less than its closing \"\"\"")
            }
            body.unicodeScalars.append(contentsOf: line[indent.count...])
        }
        pos = delimiter + 3 + hashes
        var sub = Lexer(body)
        return try sub.lexStringBody(hashes: hashes, terminated: false)
    }

    /// The body of any string literal: escapes, `\(...)` interpolation,
    /// and — with `hashes` — the raw rule. `terminated` bodies end at a
    /// closing `"` (plus the `#`s); a multi-line body is its own whole.
    private mutating func lexStringBody(hashes: Int, terminated: Bool) throws -> Token {
        var segments: [StringSegment] = []
        var current = ""
        func finish() -> Token {
            guard !segments.isEmpty else { return .string(current) }
            if !current.isEmpty { segments.append(.literal(current)) }
            return .interpolated(segments)
        }
        while true {
            guard let c = advance() else {
                if terminated { throw SwiftalkError.syntax("unterminated string literal") }
                return finish()
            }
            switch c {
            case "\"" where terminated && hashesFollow(hashes):
                pos += hashes
                return finish()
            case "\\" where hashesFollow(hashes):
                pos += hashes
                guard let e = advance() else {
                    throw SwiftalkError.syntax("unterminated escape sequence")
                }
                switch e {
                case "(":
                    if !current.isEmpty {
                        segments.append(.literal(current))
                        current = ""
                    }
                    var sub = Lexer(try scanInterpolation())
                    segments.append(.interpolation(try sub.tokenize()))
                case "\"": current.append("\"")
                case "\\": current.append("\\")
                case "n":  current.append("\n")
                case "r":  current.append("\r")
                case "t":  current.append("\t")
                case "0":  current.append("\0")
                case "u":  current.unicodeScalars.append(try lexUnicodeEscape())
                case "\n" where !terminated:
                    break                     // a line continuation: the newline is eaten
                default:
                    throw SwiftalkError.syntax("unknown escape sequence '\\\(e)'")
                }
            default:
                current.unicodeScalars.append(c)
            }
        }
    }

    /// Captures the source between `\(` and its matching `)`, respecting
    /// nested parentheses and nested string literals (which may themselves
    /// interpolate — recursion handles arbitrary depth).
    private mutating func scanInterpolation() throws -> String {
        var out = ""
        var depth = 1
        while let c = peek {
            switch c {
            case "(":
                depth += 1
                out.append("(")
                pos += 1
            case ")":
                depth -= 1
                pos += 1
                if depth == 0 { return out }
                out.append(")")
            case "\"":
                out += try scanNestedString()
            default:
                out.unicodeScalars.append(c)
                pos += 1
            }
        }
        throw SwiftalkError.syntax("unterminated '\\(' interpolation")
    }

    /// Copies a string literal verbatim while scanning an interpolation,
    /// recursing into any `\(...)` it contains.
    private mutating func scanNestedString() throws -> String {
        var out = "\""
        pos += 1  // consume opening quote
        while let c = peek {
            switch c {
            case "\"":
                pos += 1
                return out + "\""
            case "\\":
                pos += 1
                guard let e = peek else { break }
                if e == "(" {
                    pos += 1
                    out += "\\(" + (try scanInterpolation()) + ")"
                } else {
                    out += "\\"
                    out.unicodeScalars.append(e)
                    pos += 1
                }
            default:
                out.unicodeScalars.append(c)
                pos += 1
            }
        }
        throw SwiftalkError.syntax("unterminated string literal")
    }

    private mutating func lexUnicodeEscape() throws -> Unicode.Scalar {
        guard advance() == "{" else {
            throw SwiftalkError.syntax("expected '{' after \\u")
        }
        var hex = ""
        while let c = peek, c != "}" {
            hex.unicodeScalars.append(c)
            pos += 1
        }
        guard advance() == "}", let v = UInt32(hex, radix: 16),
              let scalar = Unicode.Scalar(v) else {
            throw SwiftalkError.syntax("invalid unicode escape \\u{\(hex)}")
        }
        return scalar
    }

    private mutating func lexNumber(memberIndex: Bool = false) throws -> Token {
        // Radix prefixes: 0x / 0o / 0b — and 0x floats (round 59):
        // `0x1.fep7` / `0x1p-2`, closing the round-37 debug round trip.
        if peek == "0", pos + 1 < scalars.count {
            let radix: Int? = switch scalars[pos + 1] {
            case "x": 16
            case "o": 8
            case "b": 2
            default:  nil
            }
            if let radix {
                pos += 2
                if radix == 16, let d = try lexHexFloat() {
                    return .double(d)
                }
                return .int(try lexInteger(radix: radix))
            }
        }
        var text = ""
        var isDouble = false
        digits: while let c = peek {
            switch c {
            case "0"..."9":
                text.unicodeScalars.append(c)
                pos += 1
            case "_":
                pos += 1
            case ".":
                // A decimal point only if a digit follows; otherwise it is
                // member access (`42.String()`).
                guard !memberIndex, !isDouble, pos + 1 < scalars.count,
                      ("0"..."9").contains(scalars[pos + 1]) else { break digits }
                isDouble = true
                text.append(".")
                pos += 1
            case "e", "E":
                isDouble = true
                text.unicodeScalars.append(c)
                pos += 1
                if let s = peek, s == "+" || s == "-" {
                    text.unicodeScalars.append(s)
                    pos += 1
                }
            default:
                break digits
            }
        }
        if isDouble {
            guard let d = Double(text) else {
                throw SwiftalkError.syntax("invalid number literal '\(text)'")
            }
            return .double(d)
        }
        guard let i = Int64(text) else {
            throw SwiftalkError.overflow("integer literal '\(text)' does not fit in Int")
        }
        return .int(i)
    }

    /// Tries a hex-float literal at the position right after `0x`
    /// (round 59): mantissa, optional `.fraction`, and a `p` exponent —
    /// REQUIRED whenever a fraction is present (Swift's rule), which is
    /// what keeps `0xff.description` a member access: `d` and `e` are
    /// hex digits, so without the p-requirement the fraction would eat
    /// them. Rewinds and returns nil when it is not a float after all.
    private mutating func lexHexFloat() throws -> Double? {
        func isHexDigit(_ c: UnicodeScalar) -> Bool {
            ("0"..."9").contains(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
        }
        let start = pos
        var text = "0x"
        while let c = peek, isHexDigit(c) || c == "_" {
            if c != "_" { text.unicodeScalars.append(c) }
            pos += 1
        }
        if peek == ".", pos + 1 < scalars.count, isHexDigit(scalars[pos + 1]) {
            let beforeFraction = pos
            pos += 1
            var fraction = "."
            while let c = peek, isHexDigit(c) || c == "_" {
                if c != "_" { fraction.unicodeScalars.append(c) }
                pos += 1
            }
            if peek == "p" || peek == "P" {
                text += fraction
            } else {
                pos = beforeFraction     // 0xff.description — not ours
            }
        }
        guard peek == "p" || peek == "P" else {
            pos = start                  // a plain hex integer
            return nil
        }
        text += "p"
        pos += 1
        if let sign = peek, sign == "+" || sign == "-" {
            text.unicodeScalars.append(sign)
            pos += 1
        }
        var sawDigit = false
        while let c = peek, ("0"..."9").contains(c) || c == "_" {
            if c != "_" { text.unicodeScalars.append(c); sawDigit = true }
            pos += 1
        }
        guard sawDigit, let d = Double(text) else {
            throw SwiftalkError.syntax("invalid hex-float literal '\(text)'")
        }
        return d
    }

    private mutating func lexInteger(radix: Int) throws -> Int64 {
        var text = ""
        while let c = peek, c.properties.isAlphabetic || ("0"..."9").contains(c) || c == "_" {
            if c != "_" { text.unicodeScalars.append(c) }
            pos += 1
        }
        guard !text.isEmpty, let i = Int64(text, radix: radix) else {
            throw SwiftalkError.syntax("invalid integer literal for radix \(radix): '\(text)'")
        }
        return i
    }
}
