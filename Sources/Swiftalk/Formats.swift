/// SION as a built-in (round 97): the formats a value can be read from
/// and written to — SION itself, JSON, and property lists (XML and
/// binary) — all Foundation-free. A "SION value" is any swiftalk value
/// SION can carry (§3b: nil, Bool, Int, Double, String, Data, Date,
/// and Arrays/Dictionaries of them); there is no box.

// MARK: - Base64

enum Base64 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let values: [UInt8?] = {
        var table = [UInt8?](repeating: nil, count: 256)
        for (i, c) in alphabet.enumerated() { table[Int(c)] = UInt8(i) }
        return table
    }()

    static func encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count + 2) / 3 * 4)
        var i = 0
        while i + 2 < bytes.count {
            let n = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8) | UInt32(bytes[i + 2])
            out.append(alphabet[Int(n >> 18 & 63)]); out.append(alphabet[Int(n >> 12 & 63)])
            out.append(alphabet[Int(n >> 6 & 63)]);  out.append(alphabet[Int(n & 63)])
            i += 3
        }
        let rest = bytes.count - i
        if rest == 1 {
            let n = UInt32(bytes[i]) << 16
            out.append(alphabet[Int(n >> 18 & 63)]); out.append(alphabet[Int(n >> 12 & 63)])
            out.append(UInt8(ascii: "=")); out.append(UInt8(ascii: "="))
        } else if rest == 2 {
            let n = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8)
            out.append(alphabet[Int(n >> 18 & 63)]); out.append(alphabet[Int(n >> 12 & 63)])
            out.append(alphabet[Int(n >> 6 & 63)]);  out.append(UInt8(ascii: "="))
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// nil for anything but base64 (whitespace ignored; padding required).
    static func decode(_ text: String) -> [UInt8]? {
        let chars = text.utf8.filter { $0 != 32 && $0 != 10 && $0 != 13 && $0 != 9 }
        guard chars.count % 4 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 4 * 3)
        var i = 0
        while i < chars.count {
            var n: UInt32 = 0
            var pad = 0
            for k in 0..<4 {
                let c = chars[i + k]
                if c == UInt8(ascii: "=") {
                    guard i + 4 == chars.count, k >= 2 else { return nil }   // only at the end, at most two
                    pad += 1
                    n <<= 6
                } else {
                    guard pad == 0, let v = values[Int(c)] else { return nil }
                    n = n << 6 | UInt32(v)
                }
            }
            out.append(UInt8(n >> 16 & 255))
            if pad < 2 { out.append(UInt8(n >> 8 & 255)) }
            if pad < 1 { out.append(UInt8(n & 255)) }
            i += 4
        }
        return out
    }
}

// MARK: - SION text

enum SIONFormat {
    /// `SION(text)`: swiftalk's own lexer and parser read the text, and
    /// only literal forms are admitted — no names, no calls but the
    /// SION spellings `.Date(epoch)` and `.Data("base64")` — so a SION
    /// document is data, never code. Comments, `_` digits, hex floats,
    /// escapes, and `"""` come along with the lexer.
    static func parse(_ text: String) throws -> Value {
        var lexer = Lexer(text)
        var parser = Parser(try lexer.tokenize())
        let program = try parser.parseProgram()
        guard program.count == 1, case .expression(let expr) = program[0] else {
            throw SwiftalkError.type("SION(text) reads one value")
        }
        return try value(of: expr)
    }

    private static func value(of expr: Expr) throws -> Value {
        switch expr {
        case .literal(let v):
            guard isSION(v) else { throw SwiftalkError.type("not SION: \(v.sourceString())") }
            return v
        case .unaryMinus(.literal(.int(let i))):    return .int(-i)
        case .unaryMinus(.literal(.double(let d))): return .double(-d)
        case .array(let elements):
            return .array(try elements.map(value(of:)))
        case .dictionary(let pairs):
            var d: [Value: Value] = [:]
            for (k, v) in pairs { d[try value(of: k)] = try value(of: v) }
            return .dictionary(d)
        case .call(.memberLiteral("Date"), let args) where args.count == 1 && args[0].label == nil:
            switch try value(of: args[0].expr) {
            case .double(let t): return .date(t)
            case .int(let t):    return .date(Double(t))
            case let v:          throw SwiftalkError.type(".Date() takes a number, not \(v.sourceString())")
            }
        case .call(.memberLiteral("Data"), let args) where args.count == 1 && args[0].label == nil:
            guard case .string(let b64) = try value(of: args[0].expr) else {
                throw SwiftalkError.type(".Data() takes a base64 String")
            }
            guard let bytes = Base64.decode(b64) else {
                throw SwiftalkError.type("not base64: \(b64.debugDescription)")
            }
            return .data(bytes)
        default:
            throw SwiftalkError.type("not SION: only literals, .Date(), and .Data() may appear")
        }
    }
}

// MARK: - JSON

enum JSONFormat {
    /// `.String(.json)`: lossy where JSON is poorer than SION (round 97's
    /// decision): Data → base64 String, Date → epoch number, a non-String
    /// key → its String() form; nil → null. Keys sorted, so the text is
    /// canonical. Infinite or NaN Doubles have no JSON.
    static func emit(_ value: Value) throws -> String {
        var out = ""
        try write(value, into: &out)
        return out
    }

    private static func write(_ value: Value, into out: inout String) throws {
        switch value {
        case .nil:          out += "null"
        case .bool(let b):  out += b ? "true" : "false"
        case .int(let i):   out += String(i)
        case .byte(let b):  out += String(b)
        case .double(let d):
            guard d.isFinite else { throw SwiftalkError.type("JSON has no \(d)") }
            out += Value.double(d).sourceString()
        case .string(let s): writeString(s, into: &out)
        case .data(let b):   writeString(Base64.encode(b), into: &out)
        case .date(let t):   out += Value.double(t).sourceString()
        case .array(let a):
            out += "["
            for (i, e) in a.enumerated() {
                if i > 0 { out += "," }
                try write(e, into: &out)
            }
            out += "]"
        case .dictionary(let d):
            let pairs = d.map { (key: displayString($0.key), value: $0.value) }
                .sorted { $0.key < $1.key }
            out += "{"
            for (i, p) in pairs.enumerated() {
                if i > 0 { out += "," }
                writeString(p.key, into: &out)
                out += ":"
                try write(p.value, into: &out)
            }
            out += "}"
        default:
            throw SwiftalkError.type("a \(value.typeName) has no JSON form")
        }
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case let c where c.value < 0x20:
                out += "\\u" + String(c.value, radix: 16).leftPadded(to: 4)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }

    /// `SION(json: text)`: RFC 8259, one value; numbers are Ints when
    /// they have neither fraction nor exponent and fit, else Doubles.
    static func parse(_ text: String) throws -> Value {
        var p = JSONParser(Array(text.unicodeScalars))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        guard p.pos == p.s.count else { throw p.error("unexpected text after the value") }
        return v
    }

    private struct JSONParser {
        let s: [Unicode.Scalar]
        var pos = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }
        var peek: Unicode.Scalar? { pos < s.count ? s[pos] : nil }
        func error(_ what: String) -> SwiftalkError { .type("JSON: \(what) at \(pos)") }
        mutating func skipSpace() {
            while let c = peek, c == " " || c == "\n" || c == "\r" || c == "\t" { pos += 1 }
        }
        mutating func expect(_ word: String) throws {
            for w in word.unicodeScalars {
                guard peek == w else { throw error("expected '\(word)'") }
                pos += 1
            }
        }
        mutating func value() throws -> Value {
            guard let c = peek else { throw error("unexpected end") }
            switch c {
            case "n": try expect("null");  return .nil
            case "t": try expect("true");  return .bool(true)
            case "f": try expect("false"); return .bool(false)
            case "\"": return .string(try string())
            case "[":
                pos += 1
                var a: [Value] = []
                skipSpace()
                if peek == "]" { pos += 1; return .array(a) }
                while true {
                    skipSpace()
                    a.append(try value())
                    skipSpace()
                    if peek == "," { pos += 1; continue }
                    if peek == "]" { pos += 1; return .array(a) }
                    throw error("expected ',' or ']'")
                }
            case "{":
                pos += 1
                var d: [Value: Value] = [:]
                skipSpace()
                if peek == "}" { pos += 1; return .dictionary(d) }
                while true {
                    skipSpace()
                    guard peek == "\"" else { throw error("expected a String key") }
                    let k = try string()
                    skipSpace()
                    guard peek == ":" else { throw error("expected ':'") }
                    pos += 1
                    skipSpace()
                    d[.string(k)] = try value()
                    skipSpace()
                    if peek == "," { pos += 1; continue }
                    if peek == "}" { pos += 1; return .dictionary(d) }
                    throw error("expected ',' or '}'")
                }
            case "-", "0"..."9":
                return try number()
            default:
                throw error("unexpected '\(c)'")
            }
        }
        mutating func number() throws -> Value {
            let start = pos
            var isDouble = false
            if peek == "-" { pos += 1 }
            guard let first = peek, ("0"..."9").contains(first) else { throw error("expected a digit") }
            if first == "0" { pos += 1 } else { while let c = peek, ("0"..."9").contains(c) { pos += 1 } }
            if peek == "." {
                isDouble = true; pos += 1
                guard let c = peek, ("0"..."9").contains(c) else { throw error("expected a digit after '.'") }
                while let c = peek, ("0"..."9").contains(c) { pos += 1 }
            }
            if peek == "e" || peek == "E" {
                isDouble = true; pos += 1
                if peek == "+" || peek == "-" { pos += 1 }
                guard let c = peek, ("0"..."9").contains(c) else { throw error("expected an exponent") }
                while let c = peek, ("0"..."9").contains(c) { pos += 1 }
            }
            var text = ""
            text.unicodeScalars.append(contentsOf: s[start..<pos])
            if !isDouble, let i = Int64(text) { return .int(i) }
            guard let d = Double(text) else { throw error("bad number '\(text)'") }
            return .double(d)
        }
        mutating func string() throws -> String {
            pos += 1  // the opening quote
            var out = ""
            while true {
                guard let c = peek else { throw error("unterminated string") }
                pos += 1
                switch c {
                case "\"": return out
                case "\\":
                    guard let e = peek else { throw error("unterminated escape") }
                    pos += 1
                    switch e {
                    case "\"": out += "\""
                    case "\\": out += "\\"
                    case "/":  out += "/"
                    case "b":  out += "\u{08}"
                    case "f":  out += "\u{0C}"
                    case "n":  out += "\n"
                    case "r":  out += "\r"
                    case "t":  out += "\t"
                    case "u":
                        var unit = try hex4()
                        if (0xD800...0xDBFF).contains(unit) {
                            // a surrogate pair
                            guard peek == "\\" else { throw error("lone surrogate") }
                            pos += 1
                            guard peek == "u" else { throw error("lone surrogate") }
                            pos += 1
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw error("bad surrogate pair") }
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(unit) else { throw error("bad \\u escape") }
                        out.unicodeScalars.append(scalar)
                    default:
                        throw error("unknown escape '\\\(e)'")
                    }
                case let c where c.value < 0x20:
                    throw error("control character in a string")
                default:
                    out.unicodeScalars.append(c)
                }
            }
        }
        mutating func hex4() throws -> UInt32 {
            var v: UInt32 = 0
            for _ in 0..<4 {
                guard let c = peek, let digit = c.properties.numericType != nil ? UInt32(String(c)) : hexLetter(c) else {
                    throw error("expected four hex digits")
                }
                v = v << 4 | digit
                pos += 1
            }
            return v
        }
        func hexLetter(_ c: Unicode.Scalar) -> UInt32? {
            switch c {
            case "a"..."f": return c.value - 87
            case "A"..."F": return c.value - 55
            default: return nil
            }
        }
    }
}

// MARK: - Civil dates (for property-list <date>s)

enum CivilDate {
    /// Howard Hinnant's algorithms, integer seconds — ISO 8601 `Z`.
    static func iso8601(_ epoch: Double) -> String {
        let seconds = Int64(epoch.rounded(.down))
        let days = seconds >= 0 ? seconds / 86400 : (seconds - 86399) / 86400
        let secondOfDay = seconds - days * 86400
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let year = m <= 2 ? y + 1 : y
        func pad(_ v: Int64, _ w: Int) -> String { String(v).leftPadded(to: w) }
        return "\(pad(year, 4))-\(pad(m, 2))-\(pad(d, 2))T\(pad(secondOfDay / 3600, 2)):\(pad(secondOfDay / 60 % 60, 2)):\(pad(secondOfDay % 60, 2))Z"
    }

    /// `YYYY-MM-DDTHH:MM:SS[.fff]Z` → epoch seconds; nil if malformed.
    static func epoch(fromISO8601 text: String) -> Double? {
        let s = Array(text.utf8)
        guard s.count >= 20, s[4] == 45, s[7] == 45, s[10] == 84, s[13] == 58, s[16] == 58, s.last == 90 else { return nil }
        func num(_ r: Range<Int>) -> Int64? { Int64(String(decoding: s[r], as: UTF8.self)) }
        guard let y = num(0..<4), let m = num(5..<7), let d = num(8..<10),
              let hh = num(11..<13), let mm = num(14..<16), let ss = num(17..<19),
              (1...12).contains(m), (1...31).contains(d), hh < 24, mm < 60, ss < 61 else { return nil }
        var fraction = 0.0
        if s.count > 20 {
            guard s[19] == 46, let f = Double("0." + String(decoding: s[20..<(s.count - 1)], as: UTF8.self)) else { return nil }
            fraction = f
        }
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = m > 2 ? m - 3 : m + 9
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        return Double(days * 86400 + hh * 3600 + mm * 60 + ss) + fraction
    }
}

// MARK: - Property lists, XML

enum PlistXML {
    static let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """

    static func emit(_ value: Value) throws -> String {
        var out = header
        try write(value, depth: 0, into: &out)
        out += "</plist>\n"
        return out
    }

    private static func write(_ value: Value, depth: Int, into out: inout String) throws {
        let tab = String(repeating: "\t", count: depth)
        switch value {
        case .nil:           throw SwiftalkError.type("property lists have no nil")
        case .bool(let b):   out += tab + (b ? "<true/>\n" : "<false/>\n")
        case .int(let i):    out += tab + "<integer>\(i)</integer>\n"
        case .byte(let b):   out += tab + "<integer>\(b)</integer>\n"
        case .double(let d):
            guard d.isFinite else { throw SwiftalkError.type("property lists have no \(d)") }
            out += tab + "<real>\(Value.double(d).sourceString())</real>\n"
        case .string(let s): out += tab + "<string>\(escape(s))</string>\n"
        case .data(let b):   out += tab + "<data>\(Base64.encode(b))</data>\n"
        case .date(let t):   out += tab + "<date>\(CivilDate.iso8601(t))</date>\n"
        case .array(let a):
            if a.isEmpty { out += tab + "<array/>\n"; return }
            out += tab + "<array>\n"
            for e in a { try write(e, depth: depth + 1, into: &out) }
            out += tab + "</array>\n"
        case .dictionary(let d):
            if d.isEmpty { out += tab + "<dict/>\n"; return }
            var pairs: [(String, Value)] = []
            for (k, v) in d {
                guard case .string(let key) = k else {
                    throw SwiftalkError.type("property-list keys are Strings, not \(k.typeName)")
                }
                pairs.append((key, v))
            }
            pairs.sort { $0.0 < $1.0 }
            out += tab + "<dict>\n"
            for (k, v) in pairs {
                out += tab + "\t<key>\(escape(k))</key>\n"
                try write(v, depth: depth + 1, into: &out)
            }
            out += tab + "</dict>\n"
        default:
            throw SwiftalkError.type("a \(value.typeName) has no property-list form")
        }
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    /// `SION(propertyList: text)`: the plist subset of XML — elements,
    /// text, entities, comments, the prolog — nothing more.
    static func parse(_ text: String) throws -> Value {
        var p = XMLParser(Array(text.unicodeScalars))
        try p.skipProlog()
        let (name, empty) = try p.openTag()
        guard name == "plist" else { throw p.error("expected <plist>") }
        guard !empty else { throw p.error("an empty <plist/>") }
        p.skipSpace()
        let v = try p.element()
        p.skipSpace()
        try p.closeTag("plist")
        return v
    }

    private struct XMLParser {
        let s: [Unicode.Scalar]
        var pos = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }
        var peek: Unicode.Scalar? { pos < s.count ? s[pos] : nil }
        func error(_ what: String) -> SwiftalkError { .type("property list: \(what) at \(pos)") }
        func starts(with text: String) -> Bool {
            let t = Array(text.unicodeScalars)
            return pos + t.count <= s.count && Array(s[pos..<(pos + t.count)]) == t
        }
        mutating func skipSpace() {
            while true {
                while let c = peek, c == " " || c == "\n" || c == "\r" || c == "\t" { pos += 1 }
                if starts(with: "<!--") {
                    pos += 4
                    while pos < s.count, !starts(with: "-->") { pos += 1 }
                    pos += 3
                    continue
                }
                return
            }
        }
        mutating func skipProlog() throws {
            skipSpace()
            while starts(with: "<?") || starts(with: "<!") {
                while let c = peek, c != ">" { pos += 1 }
                guard peek == ">" else { throw error("unterminated prolog") }
                pos += 1
                skipSpace()
            }
        }
        mutating func name() -> String {
            var n = ""
            while let c = peek, c != ">" && c != "/" && c != " " && c != "\n" && c != "\t" && c != "\r" {
                n.unicodeScalars.append(c); pos += 1
            }
            return n
        }
        /// `<name ...>` or `<name/>`; attributes are skipped.
        mutating func openTag() throws -> (name: String, empty: Bool) {
            guard peek == "<" else { throw error("expected '<'") }
            pos += 1
            let n = name()
            guard !n.isEmpty else { throw error("expected an element name") }
            while let c = peek, c != ">" && c != "/" { pos += 1 }
            var empty = false
            if peek == "/" { empty = true; pos += 1 }
            guard peek == ">" else { throw error("expected '>'") }
            pos += 1
            return (n, empty)
        }
        mutating func closeTag(_ expected: String) throws {
            guard starts(with: "</") else { throw error("expected </\(expected)>") }
            pos += 2
            let n = name()
            guard n == expected, peek == ">" else { throw error("expected </\(expected)>") }
            pos += 1
        }
        mutating func text(until tag: String) throws -> String {
            var out = ""
            while let c = peek {
                if c == "<" { break }
                pos += 1
                if c == "&" {
                    var entity = ""
                    while let e = peek, e != ";" { entity.unicodeScalars.append(e); pos += 1 }
                    guard peek == ";" else { throw error("unterminated entity") }
                    pos += 1
                    switch entity {
                    case "amp":  out += "&"
                    case "lt":   out += "<"
                    case "gt":   out += ">"
                    case "quot": out += "\""
                    case "apos": out += "'"
                    default:
                        guard entity.hasPrefix("#"),
                              let v = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16)
                                                             : UInt32(entity.dropFirst(1)),
                              let scalar = Unicode.Scalar(v) else { throw error("unknown entity &\(entity);") }
                        out.unicodeScalars.append(scalar)
                    }
                } else {
                    out.unicodeScalars.append(c)
                }
            }
            try closeTag(tag)
            return out
        }
        mutating func element() throws -> Value {
            let (n, empty) = try openTag()
            switch n {
            case "true":  guard empty else { throw error("<true> is <true/>") }; return .bool(true)
            case "false": guard empty else { throw error("<false> is <false/>") }; return .bool(false)
            case "string":
                return .string(empty ? "" : try text(until: "string"))
            case "integer":
                let t = empty ? "" : try text(until: "integer").trimmed()
                guard let i = Int64(t) else { throw error("bad <integer> '\(t)'") }
                return .int(i)
            case "real":
                let t = empty ? "" : try text(until: "real").trimmed()
                guard let d = Double(t) else { throw error("bad <real> '\(t)'") }
                return .double(d)
            case "date":
                let t = empty ? "" : try text(until: "date").trimmed()
                guard let e = CivilDate.epoch(fromISO8601: t) else { throw error("bad <date> '\(t)'") }
                return .date(e)
            case "data":
                let t = empty ? "" : try text(until: "data")
                guard let b = Base64.decode(t) else { throw error("bad <data>") }
                return .data(b)
            case "array":
                var a: [Value] = []
                if empty { return .array(a) }
                while true {
                    skipSpace()
                    if starts(with: "</") { try closeTag("array"); return .array(a) }
                    a.append(try element())
                }
            case "dict":
                var d: [Value: Value] = [:]
                if empty { return .dictionary(d) }
                while true {
                    skipSpace()
                    if starts(with: "</") { try closeTag("dict"); return .dictionary(d) }
                    let (kn, kempty) = try openTag()
                    guard kn == "key" else { throw error("expected <key>") }
                    let key = kempty ? "" : try text(until: "key")
                    skipSpace()
                    d[.string(key)] = try element()
                }
            default:
                throw error("unknown element <\(n)>")
            }
        }
    }
}

// MARK: - Property lists, binary (bplist00)

enum PlistBinary {
    /// `x.Data(.propertyList)`: Apple's bplist00 — an object table,
    /// an offset table, a 32-byte trailer. No uniquing; big-endian.
    static func emit(_ value: Value) throws -> [UInt8] {
        var objects: [Value] = []
        func flatten(_ v: Value) throws -> Int {
            let index = objects.count
            objects.append(v)
            switch v {
            case .nil: throw SwiftalkError.type("property lists have no nil")
            case .bool, .int, .double, .string, .data, .date: break
            case .array(let a):
                for e in a { _ = try flatten(e) }
            case .dictionary(let d):
                for k in d.keys {
                    guard case .string = k else {
                        throw SwiftalkError.type("property-list keys are Strings, not \(k.typeName)")
                    }
                }
                for (k, v) in d.sorted(by: { displayString($0.key) < displayString($1.key) }) {
                    _ = try flatten(k); _ = try flatten(v)
                }
            default: throw SwiftalkError.type("a \(v.typeName) has no property-list form")
            }
            return index
        }
        _ = try flatten(value)
        // child indices: pre-order, so a container's children follow it —
        // recompute them the same way while writing
        let refSize = byteSize(objects.count)
        var out: [UInt8] = Array("bplist00".utf8)
        var offsets: [Int] = []
        var cursor = 0
        func childIndices(of v: Value, at index: Int) -> [Int] {
            // the children of object `index`, pre-order: walk sizes
            var result: [Int] = []
            var next = index + 1
            func size(_ v: Value) -> Int {
                switch v {
                case .array(let a): return 1 + a.reduce(0) { $0 + size($1) }
                case .dictionary(let d): return 1 + d.reduce(0) { $0 + 1 + size($1.value) }
                default: return 1
                }
            }
            switch v {
            case .array(let a):
                for e in a { result.append(next); next += size(e) }
            case .dictionary(let d):
                var keys: [Int] = [], values: [Int] = []
                for (_, val) in d.sorted(by: { displayString($0.key) < displayString($1.key) }) {
                    keys.append(next); next += 1
                    values.append(next); next += size(val)
                }
                result = keys + values
            default: break
            }
            return result
        }
        for (index, v) in objects.enumerated() {
            offsets.append(out.count)
            switch v {
            case .bool(let b): out.append(b ? 0x09 : 0x08)
            case .int(let i):
                if i >= 0 && i <= 255 { out.append(0x10); out.append(UInt8(i)) }
                else if i >= 0 && i <= 65535 { out.append(0x11); out += bigEndian(UInt64(i), 2) }
                else if i >= 0 && i <= 4294967295 { out.append(0x12); out += bigEndian(UInt64(i), 4) }
                else { out.append(0x13); out += bigEndian(UInt64(bitPattern: i), 8) }
            case .double(let d):
                guard d.isFinite else { throw SwiftalkError.type("property lists have no \(d)") }
                out.append(0x23); out += bigEndian(d.bitPattern, 8)
            case .date(let t):
                out.append(0x33); out += bigEndian((t - 978307200).bitPattern, 8)
            case .data(let b):
                out += marker(0x40, count: b.count); out += b
            case .string(let s):
                if s.utf8.allSatisfy({ $0 < 0x80 }) {
                    let bytes = Array(s.utf8)
                    out += marker(0x50, count: bytes.count); out += bytes
                } else {
                    let units = Array(s.utf16)
                    out += marker(0x60, count: units.count)
                    for u in units { out += bigEndian(UInt64(u), 2) }
                }
            case .array(let a):
                out += marker(0xA0, count: a.count)
                for c in childIndices(of: v, at: index) { out += bigEndian(UInt64(c), refSize) }
            case .dictionary(let d):
                out += marker(0xD0, count: d.count)
                for c in childIndices(of: v, at: index) { out += bigEndian(UInt64(c), refSize) }
            default: break
            }
            cursor = out.count
        }
        let offsetTableOffset = cursor
        let offsetSize = byteSize(offsetTableOffset)
        for o in offsets { out += bigEndian(UInt64(o), offsetSize) }
        // trailer
        out += [0, 0, 0, 0, 0, 0]
        out.append(UInt8(offsetSize))
        out.append(UInt8(refSize))
        out += bigEndian(UInt64(objects.count), 8)
        out += bigEndian(0, 8)
        out += bigEndian(UInt64(offsetTableOffset), 8)
        return out
    }

    private static func byteSize(_ n: Int) -> Int {
        n <= 0xFF ? 1 : n <= 0xFFFF ? 2 : n <= 0xFFFF_FFFF ? 4 : 8
    }
    private static func bigEndian(_ v: UInt64, _ size: Int) -> [UInt8] {
        (0..<size).reversed().map { UInt8(v >> (8 * UInt64($0)) & 0xFF) }
    }
    private static func marker(_ type: UInt8, count: Int) -> [UInt8] {
        if count < 15 { return [type | UInt8(count)] }
        var out: [UInt8] = [type | 0x0F]
        if count <= 0xFF { out.append(0x10); out += bigEndian(UInt64(count), 1) }
        else if count <= 0xFFFF { out.append(0x11); out += bigEndian(UInt64(count), 2) }
        else if count <= 0xFFFF_FFFF { out.append(0x12); out += bigEndian(UInt64(count), 4) }
        else { out.append(0x13); out += bigEndian(UInt64(count), 8) }
        return out
    }

    /// `SION(propertyList: data)`: reads bplist00 back.
    static func parse(_ bytes: [UInt8]) throws -> Value {
        func fail(_ what: String) -> SwiftalkError { .type("binary property list: \(what)") }
        guard bytes.count >= 40, Array(bytes[0..<7]) == Array("bplist0".utf8) else {
            throw fail("not a bplist00")
        }
        func readBE(_ at: Int, _ size: Int) throws -> UInt64 {
            guard at >= 0, at + size <= bytes.count else { throw fail("truncated") }
            var v: UInt64 = 0
            for i in 0..<size { v = v << 8 | UInt64(bytes[at + i]) }
            return v
        }
        let trailer = bytes.count - 32
        let offsetSize = Int(bytes[trailer + 6])
        let refSize = Int(bytes[trailer + 7])
        let count = Int(try readBE(trailer + 8, 8))
        let top = Int(try readBE(trailer + 16, 8))
        let tableOffset = Int(try readBE(trailer + 24, 8))
        guard (1...8).contains(offsetSize), (1...8).contains(refSize), count > 0, top < count else {
            throw fail("bad trailer")
        }
        var offsets: [Int] = []
        for i in 0..<count { offsets.append(Int(try readBE(tableOffset + i * offsetSize, offsetSize))) }
        var visiting = Set<Int>()
        func object(_ index: Int) throws -> Value {
            guard index < count else { throw fail("bad object reference") }
            guard visiting.insert(index).inserted else { throw fail("cyclic reference") }
            defer { visiting.remove(index) }
            var p = offsets[index]
            guard p < bytes.count else { throw fail("bad offset") }
            let marker = bytes[p]
            p += 1
            let type = marker & 0xF0
            var n = Int(marker & 0x0F)
            func readCount() throws {
                if n == 0x0F {
                    guard p < bytes.count, bytes[p] & 0xF0 == 0x10 else { throw fail("bad count") }
                    let size = 1 << Int(bytes[p] & 0x0F)
                    n = Int(try readBE(p + 1, size))
                    p += 1 + size
                }
            }
            switch type {
            case 0x00:
                switch marker {
                case 0x08: return .bool(false)
                case 0x09: return .bool(true)
                default: throw fail("unsupported marker \(marker)")
                }
            case 0x10:
                let size = 1 << n
                let raw = try readBE(p, size)
                return .int(size == 8 ? Int64(bitPattern: raw) : Int64(raw))
            case 0x20:
                let size = 1 << n
                guard size == 8 || size == 4 else { throw fail("unsupported real size") }
                let raw = try readBE(p, size)
                return .double(size == 8 ? Double(bitPattern: raw) : Double(Float(bitPattern: UInt32(raw))))
            case 0x30:
                guard n == 3 else { throw fail("unsupported date size") }
                return .date(Double(bitPattern: try readBE(p, 8)) + 978307200)
            case 0x40:
                try readCount()
                guard p + n <= bytes.count else { throw fail("truncated data") }
                return .data(Array(bytes[p..<(p + n)]))
            case 0x50:
                try readCount()
                guard p + n <= bytes.count else { throw fail("truncated string") }
                return .string(String(decoding: bytes[p..<(p + n)], as: UTF8.self))
            case 0x60:
                try readCount()
                var units: [UInt16] = []
                for i in 0..<n { units.append(UInt16(try readBE(p + 2 * i, 2))) }
                return .string(String(decoding: units, as: UTF16.self))
            case 0xA0:
                try readCount()
                var a: [Value] = []
                for i in 0..<n { a.append(try object(Int(try readBE(p + i * refSize, refSize)))) }
                return .array(a)
            case 0xD0:
                try readCount()
                var d: [Value: Value] = [:]
                for i in 0..<n {
                    let k = try object(Int(try readBE(p + i * refSize, refSize)))
                    let v = try object(Int(try readBE(p + (n + i) * refSize, refSize)))
                    d[k] = v
                }
                return .dictionary(d)
            default:
                throw fail("unsupported marker \(marker)")
            }
        }
        return try object(top)
    }
}

extension String {
    func leftPadded(to width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
    func trimmed() -> String {
        var s = Substring(self)
        while let f = s.first, f == " " || f == "\n" || f == "\t" || f == "\r" { s = s.dropFirst() }
        while let l = s.last, l == " " || l == "\n" || l == "\t" || l == "\r" { s = s.dropLast() }
        return String(s)
    }
}
