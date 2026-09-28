import Swiftalk

// `BigInt` — arbitrary-precision integers (round 201), a module: the type
// `BigInt` behind the literal `123n` — JS's spelling, the `n` mandatory,
// whose grammar is the core's — and its arithmetic. The engine is
// swift-bignum's `BigInt` (github.com/dankogai/swift-bignum), vendored
// in `Vendored/` rather than depended on. Preimported by the CLI;
// `import from "BigInt"` otherwise.
//
//     let f = (1n...100n).reduce(1n, *)      // no overflow, ever      (Range is Int-only; see .power)
//     2n ** 256n                              // 115792089237316195423570985008687907853269984665640564039457584007913129639936n
//     BigInt(Int.max) + 1n                    // 9223372036854775808n
//     BigInt("0xdead_beef"), BigInt(1e3)      // from a String (any radix prefix), an integral Double
//     b.Int()                                 // back, or an overflow error; b.Double() approximates
//     b.String(.hex), b.String(radix: 36)     // 0x...n (re-enters), bare digits
//     b.power(e), b.power(e, m), b.squareRoot(), b.gcd(c), b.magnitude, b.signum, b.bitWidth
//
// Strict, as swiftalk's numbers are: a BigInt meets a BigInt, not an Int
// or a Double — convert first. Division truncates and `%` follows the
// dividend's sign, as Int's do; dividing by zero is the core's error.

final class BigIntValue: Swiftalk.HostValue {
    let n: BigInt
    let type: Swiftalk.Value
    init(_ n: BigInt, type: Swiftalk.Value) { self.n = n; self.type = type }

    var typeName: String { "BigInt" }
    func make(_ v: BigInt) -> Swiftalk.Value { .host(BigIntValue(v, type: type)) }

    /// Parses what the literal and `BigInt(s)` accept: an optional sign,
    /// a radix prefix (`0x`, `0o`, `0b`), `_` separators, a trailing `n`.
    static func parse(_ text: String) -> BigInt? {
        var s = Substring(text.filter { $0 != "_" })
        if s.hasSuffix("n") { s = s.dropLast() }
        var negative = false
        if s.hasPrefix("-") { negative = true; s = s.dropFirst() } else if s.hasPrefix("+") { s = s.dropFirst() }
        var radix = 10
        if s.hasPrefix("0x") || s.hasPrefix("0X") { radix = 16; s = s.dropFirst(2) }
        else if s.hasPrefix("0o") || s.hasPrefix("0O") { radix = 8; s = s.dropFirst(2) }
        else if s.hasPrefix("0b") || s.hasPrefix("0B") { radix = 2; s = s.dropFirst(2) }
        guard !s.isEmpty, let v = BigInt(s, radix: radix) else { return nil }
        return negative ? -v : v
    }

    // ---- members ----

    private func other(_ v: Swiftalk.Value, _ what: String) throws -> BigInt {
        if case .host(let h) = v, let b = h as? BigIntValue { return b.n }
        throw Swiftalk.Error.type("\(what) takes a BigInt, not \(v.typeName) — BigInt(x) converts")
    }

    func member(_ name: String, args: [Swiftalk.Value], called: Bool) throws -> Swiftalk.Value? {
        switch (name, called) {
        case ("BigInt", true):   return .host(self)
        case ("Int", true):
            guard let i = Int64(exactly: n) else { throw Swiftalk.Error.overflow("\(n)n does not fit in an Int") }
            return .int(i)
        case ("Double", true):   return .double(Double(n))
        case ("String", true):
            // .String() is the source form; .String(.hex/.oct/.bin) a literal-ready
            // prefixed form; .String(radix) / .String(radix: r) bare digits
            guard let format = args.first else { return .string(sourceString(debug: false)) }
            guard args.count == 1 else { throw Swiftalk.Error.type("BigInt.String() takes at most one format") }
            switch format {
            case .string("hex"): return .string(prefixed(radix: 16))
            case .string("oct"): return .string(prefixed(radix: 8))
            case .string("bin"): return .string(prefixed(radix: 2))
            case .string("sign"): return .string((n < 0 ? "" : "+") + n.toString(radix: 10))
            case .int(let r) where (2...36).contains(r): return .string(n.toString(radix: Int(r)))
            default: throw Swiftalk.Error.type("BigInt.String() takes .hex, .oct, .bin, .sign, or a radix 2...36, not \(format.sourceString())")
            }
        case ("magnitude", false): return make(BigInt(n.magnitude))
        case ("signum", false):    return .int(Int64(n.signum()))
        case ("isZero", false):    return .bool(n.isZero)
        case ("bitWidth", false):  return .int(Int64(n.bitWidth))
        case ("trailingZeroBitCount", false): return .int(Int64(n.trailingZeroBitCount))
        case ("power", true):
            guard (1...2).contains(args.count) else { throw Swiftalk.Error.type("BigInt.power(exponent) or .power(exponent, modulus)") }
            let e: BigInt
            switch args[0] {
            case .int(let i):  e = BigInt(i)
            case .host(let h): guard let b = h as? BigIntValue else { fallthrough }; e = b.n
            default: throw Swiftalk.Error.type("BigInt.power takes an Int or BigInt exponent, not \(args[0].typeName)")
            }
            guard e >= 0 else { throw Swiftalk.Error.type("BigInt.power: a negative exponent has no integer answer") }
            if args.count == 2 {
                let m = try other(args[1], "BigInt.power(exponent, modulus)")
                guard !m.isZero else { throw Swiftalk.Error.zeroDivision }
                return make(n.power(e, mod: m))
            }
            return make(n.power(e))
        case ("squareRoot", true):
            guard args.isEmpty else { throw Swiftalk.Error.type("BigInt.squareRoot() takes no arguments") }
            guard n >= 0 else { throw Swiftalk.Error.type("BigInt.squareRoot() of a negative: \(n)n") }
            return make(n.squareRoot())
        case ("gcd", true):
            guard args.count == 1 else { throw Swiftalk.Error.type("BigInt.gcd(other) takes one BigInt") }
            return make(n.greatestCommonDivisor(with: try other(args[0], "BigInt.gcd")))
        default: return nil
        }
    }

    private func prefixed(radix: Int) -> String {
        let prefix = radix == 16 ? "0x" : radix == 8 ? "0o" : "0b"
        return (n < 0 ? "-" : "") + prefix + n.magnitude.toString(radix: radix) + "n"
    }

    // ---- operators (the core asks; nil declines to its own meaning) ----

    static let operators: Set<String> = ["infix:+", "infix:-", "infix:*", "infix:/", "infix:%", "infix:**", "infix:<",
                                         "infix:+&", "infix:+|", "infix:+^", "infix:+<", "infix:+>",
                                         "prefix:-", "prefix:+", "prefix:+^"]
    func hasOperator(_ key: String) -> Bool { BigIntValue.operators.contains(key) }

    func operate(_ key: String, _ operands: [Swiftalk.Value]) throws -> Swiftalk.Value? {
        guard BigIntValue.operators.contains(key) else { return nil }
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        let op = parts[1]
        if parts[0] == "prefix" {
            switch op {
            case "-": return make(-n)
            case "+": return make(n)
            default:  return make(~n)
            }
        }
        guard operands.count == 2 else { return nil }
        // strictness: the other side must be a BigInt too — say so, rather
        // than the core's generic "not defined between"
        let sides = try operands.map { v -> BigInt in
            if case .host(let h) = v, let b = h as? BigIntValue { return b.n }
            switch v {
            case .int, .double, .byte:
                throw Swiftalk.Error.type("'\(op)' between BigInt and \(v.typeName): convert first — BigInt(x), or b.Int()")
            default:
                throw Swiftalk.Error.type("'\(op)' is not defined between \(operands[0].typeName) and \(operands[1].typeName)")
            }
        }
        let (a, b) = (sides[0], sides[1])
        switch op {
        case "+": return make(a + b)
        case "-": return make(a - b)
        case "*": return make(a * b)
        case "/", "%":
            guard !b.isZero else { throw Swiftalk.Error.zeroDivision }
            return make(op == "/" ? a / b : a % b)
        case "**":
            guard b >= 0 else { throw Swiftalk.Error.type("'**' with a negative BigInt exponent has no integer answer") }
            return make(a.power(b))
        case "<":  return .bool(a < b)
        case "+&": return make(a & b)
        case "+|": return make(a | b)
        case "+^": return make(a ^ b)
        case "+<", "+>":
            guard let shift = Int(exactly: b) else { throw Swiftalk.Error.type("a shift count must fit an Int") }
            return make(op == "+<" ? a << shift : a >> shift)
        default: return nil
        }
    }

    func isEqual(to other: any Swiftalk.HostValue) -> Bool { (other as? BigIntValue)?.n == n }
    func hash(into hasher: inout Hasher) { hasher.combine(n) }
    /// `123n`: re-enters (§3d); the debug form is hex, as Int's is (round 37)
    func sourceString(debug: Bool) -> String {
        debug ? (n < 0 ? "-0x" : "+0x") + n.magnitude.toString(radix: 16) + "n" : n.toString(radix: 10) + "n"
    }
    /// `case 42n:` — equality; a non-BigInt subject is no match (and, binding, an error)
    func patternMatch(_ subject: Swiftalk.Value, binding: Bool) throws -> Swiftalk.Value? {
        guard case .host(let h) = subject, let b = h as? BigIntValue else {
            if binding { throw Swiftalk.Error.type("a BigInt case needs a BigInt subject, not \(subject.typeName)") }
            return nil
        }
        return b.n == n ? subject : nil
    }
}

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "BigInt")
    final class TypeBox { var value: Swiftalk.Value = .nil }
    let box = TypeBox()

    /// `BigInt(x)`: from an Int, a Byte, an integral Double, a String (the
    /// literal's spelling, any radix prefix, `_`, a trailing `n`), or a
    /// BigInt; `BigInt(s, radix)` reads bare digits in that radix; `BigInt()` is 0n.
    box.value = m.type("BigInt") { args in
        let make = { (v: BigInt) -> Swiftalk.Value in .host(BigIntValue(v, type: box.value)) }
        switch args.count {
        case 0: return make(0)
        case 1:
            switch args[0] {
            case .int(let i):    return make(BigInt(i))
            case .byte(let b):   return make(BigInt(b))
            case .double(let d):
                guard d.isFinite, d == d.rounded(.towardZero) else {
                    throw Swiftalk.Error.type("BigInt(\(args[0].sourceString())): not an integer — round it first")
                }
                return make(BigInt(d))
            case .string(let s):
                guard let v = BigIntValue.parse(s) else { throw Swiftalk.Error.type("BigInt(\"\(s)\"): not an integer literal") }
                return make(v)
            case .host(let h):
                if let b = h as? BigIntValue { return .host(b) }
                throw Swiftalk.Error.type("cannot convert \(args[0].typeName) to BigInt")
            default:
                throw Swiftalk.Error.type("cannot convert \(args[0].typeName) to BigInt")
            }
        case 2:
            guard case .string(let s) = args[0], case .int(let r) = args[1], (2...36).contains(r) else {
                throw Swiftalk.Error.type("BigInt(digits, radix) takes a String and a radix 2...36")
            }
            var text = Substring(s.filter { $0 != "_" })
            var negative = false
            if text.hasPrefix("-") { negative = true; text = text.dropFirst() }
            guard !text.isEmpty, let v = BigInt(text, radix: Int(r)) else {
                throw Swiftalk.Error.type("BigInt(\"\(s)\", \(r)): not a radix-\(r) integer")
            }
            return make(negative ? -v : v)
        default:
            throw Swiftalk.Error.type("BigInt(x) or BigInt(digits, radix)")
        }
    }
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
