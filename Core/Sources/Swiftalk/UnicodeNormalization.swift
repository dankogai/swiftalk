/// Unicode normalization (round 137): NFD, NFC, NFKD, NFKC per UAX #15,
/// Foundation-free — the mappings from `UnicodeTables` (generated from
/// the UCD), canonical combining classes from the standard library,
/// Hangul by algorithm. `"e\u{301}".normalize(with: .nfc)` is `"é"`.
enum UnicodeNormalization {
    enum Form: String { case nfc, nfd, nfkc, nfkd }

    static func normalize(_ s: String, _ form: Form) -> String {
        let compat = form == .nfkc || form == .nfkd
        var scalars = decompose(Array(s.unicodeScalars.map(\.value)), compatibility: compat)
        if form == .nfc || form == .nfkc { scalars = compose(scalars) }
        var out = String.UnicodeScalarView()
        for v in scalars { out.append(Unicode.Scalar(v)!) }
        return String(out)
    }

    // MARK: tables, parsed once

    nonisolated(unsafe) private static let canonical: [UInt32: [UInt32]] = parse(UnicodeTables.canonicalDecompositions)
    nonisolated(unsafe) private static let compatibility: [UInt32: [UInt32]] = parse(UnicodeTables.compatibilityDecompositions)
    /// (first, second) → composite, for the primary composites: canonical
    /// pairs not under Full_Composition_Exclusion.
    nonisolated(unsafe) private static let pairs: [UInt64: UInt32] = {
        var map: [UInt64: UInt32] = [:]
        for (cp, m) in canonical where m.count == 2 && !excluded(cp) {
            map[UInt64(m[0]) << 32 | UInt64(m[1])] = cp
        }
        return map
    }()

    private static func parse(_ chunks: [String]) -> [UInt32: [UInt32]] {
        var map: [UInt32: [UInt32]] = [:]
        for entry in chunks.joined().split(separator: ";") {
            let parts = entry.split(separator: ":")
            map[UInt32(parts[0], radix: 16)!] = parts[1].split(separator: " ").map { UInt32($0, radix: 16)! }
        }
        return map
    }

    private static func excluded(_ cp: UInt32) -> Bool {
        UnicodeTables.compositionExclusions.contains { $0.0 <= cp && cp <= $0.1 }
    }

    private static func ccc(_ v: UInt32) -> UInt8 {
        Unicode.Scalar(v)?.properties.canonicalCombiningClass.rawValue ?? 0
    }

    // MARK: Hangul (UAX #15 §3.12)

    private static let sBase: UInt32 = 0xAC00, lBase: UInt32 = 0x1100, vBase: UInt32 = 0x1161, tBase: UInt32 = 0x11A7
    private static let lCount: UInt32 = 19, vCount: UInt32 = 21, tCount: UInt32 = 28
    private static let nCount = vCount * tCount, sCount = lCount * nCount

    // MARK: decomposition + canonical ordering

    private static func decompose(_ input: [UInt32], compatibility compat: Bool) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(input.count)
        func push(_ v: UInt32) {
            if v >= sBase, v < sBase + sCount {                       // a Hangul syllable: L V [T]
                let i = v - sBase
                out.append(lBase + i / nCount)
                out.append(vBase + (i % nCount) / tCount)
                let t = tBase + i % tCount
                if t != tBase { out.append(t) }
                return
            }
            if let m = canonical[v] ?? (compat ? compatibility[v] : nil) {
                for x in m { push(x) }                                 // mappings are not always fully decomposed
                return
            }
            out.append(v)
        }
        for v in input { push(v) }
        // canonical ordering: each run of non-starters, stably sorted by class
        var i = 0
        while i < out.count {
            guard ccc(out[i]) != 0 else { i += 1; continue }
            var j = i
            while j < out.count, ccc(out[j]) != 0 { j += 1 }
            if j - i > 1 {
                let run = out[i..<j].enumerated().sorted { (ccc($0.element), $0.offset) < (ccc($1.element), $1.offset) }.map(\.element)
                out.replaceSubrange(i..<j, with: run)
            }
            i = j
        }
        return out
    }

    // MARK: canonical composition

    private static func composite(_ a: UInt32, _ b: UInt32) -> UInt32? {
        if a >= lBase, a < lBase + lCount, b >= vBase, b < vBase + vCount {
            return sBase + ((a - lBase) * vCount + (b - vBase)) * tCount           // L + V → LV
        }
        if a >= sBase, a < sBase + sCount, (a - sBase) % tCount == 0, b > tBase, b < tBase + tCount {
            return a + (b - tBase)                                                 // LV + T → LVT
        }
        return pairs[UInt64(a) << 32 | UInt64(b)]
    }

    private static func compose(_ input: [UInt32]) -> [UInt32] {
        guard !input.isEmpty else { return input }
        var out: [UInt32] = [input[0]]
        var starter = ccc(input[0]) == 0 ? 0 : -1
        var lastClass: Int = ccc(input[0]) == 0 ? 0 : 256          // a leading non-starter blocks
        for v in input.dropFirst() {
            let cc = Int(ccc(v))
            if starter >= 0, lastClass < cc || lastClass == 0, let c = composite(out[starter], v) {
                out[starter] = c                                      // lastClass unchanged: the blocker, if any, stays
                continue
            }
            if cc == 0 { starter = out.count }
            lastClass = cc
            out.append(v)
        }
        return out
    }
}

/// `.escaped()` / `.unescaped()` (round 137): every non-ASCII scalar as
/// `\u{hex}` and a backslash as `\\`, so the text is ASCII and re-enters
/// a string literal; `unescaped` reads the literal escapes back — `\u{}`,
/// `\\`, `\n`, `\t`, `\r`, `\0`, `\"`, `\'` — and rejects anything else.
enum StringEscapes {
    static func escaped(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\":                 out += "\\\\"
            case let c where c.isASCII: out.unicodeScalars.append(c)
            default:                   out += "\\u{" + String(scalar.value, radix: 16) + "}"
            }
        }
        return out
    }

    static func unescaped(_ s: String) throws -> String {
        var out = String.UnicodeScalarView()
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let e = it.next() else { throw SwiftalkError.type("unescaped: a trailing backslash") }
            switch e {
            case "\\": out.append("\\")
            case "n":  out.append("\n")
            case "t":  out.append("\t")
            case "r":  out.append("\r")
            case "0":  out.append("\0")
            case "\"": out.append("\"")
            case "'":  out.append("'")
            case "u":
                guard it.next() == "{" else { throw SwiftalkError.type("unescaped: \\u needs {hex}") }
                var hex = ""
                while let h = it.next(), h != "}" { hex.unicodeScalars.append(h) }
                guard !hex.isEmpty, hex.count <= 8, let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) else {
                    throw SwiftalkError.type("unescaped: invalid unicode escape \\u{\(hex)}")
                }
                out.append(scalar)
            default:
                throw SwiftalkError.type("unescaped: unknown escape \\\(e)")
            }
        }
        return String(out)
    }
}
