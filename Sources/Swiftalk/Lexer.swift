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
            switch c {
            case " ", "\t", "\r":
                pos += 1
            case "\n":
                pos += 1
                if !suppressNewlines, tokens.last != nil, tokens.last != .newline {
                    tokens.append(.newline)
                }
            case "/":
                // comment or the division operator
                if pos + 1 < scalars.count, scalars[pos + 1] == "/" {
                    while let c = peek, c != "\n" { pos += 1 }
                } else if pos + 1 < scalars.count, scalars[pos + 1] == "*" {
                    try skipBlockComment()
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
            case ":", ",", "+", "-", "*", ";":
                pos += 1
                tokens.append(.punct(Character(c)))
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
                tokens.append(try lexStringToken())
            case "0"..."9":
                tokens.append(try lexNumber())
            case let c where c.properties.isAlphabetic || c == "_":
                tokens.append(.identifier(lexIdentifier()))
            default:
                throw SwiftalkError.syntax("unexpected character '\(c)'")
            }
        }
        return tokens
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
    private mutating func lexStringToken() throws -> Token {
        pos += 1  // consume opening quote
        var segments: [StringSegment] = []
        var current = ""
        while true {
            guard let c = advance() else {
                throw SwiftalkError.syntax("unterminated string literal")
            }
            switch c {
            case "\"":
                guard !segments.isEmpty else { return .string(current) }
                if !current.isEmpty { segments.append(.literal(current)) }
                return .interpolated(segments)
            case "\\":
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

    private mutating func lexNumber() throws -> Token {
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
                guard !isDouble, pos + 1 < scalars.count,
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
