import Swiftalk
import BigNum

// `BigRat` — exact rationals (round 203), a module beside BigInt: a
// BigInt over a BigInt, reduced on construction, so `BigRat(1, 3) * 3n`
// is not what you write (strict: a BigRat meets a BigRat) but
// `BigRat(1, 3) * BigRat(3) == BigRat(1)` is exactly true. The engine is
// swift-bignum's `BigRat`, in the shared `modules/BigNum` library.
// Preimported by the CLI; `import from "BigRat"` otherwise.
//
//     BigRat(1, 3) + BigRat(1, 6)             // BigRat(1, 2) — the source form re-enters
//     BigRat(0.1)                             // BigRat(3602879701896397, 36028797018963968): the Double, exactly
//     BigRat("0.1"), BigRat("-2/3"), BigRat("1e-2")   // from text: 1/10, -2/3, 1/100
//     r.numerator, r.denominator              // BigInts (the BigInt module's), the sign in the numerator
//     r.Double(), r.BigInt(), r.Int()         // nearest Double; truncation toward zero
//     r.rounded(), r.rounded(.down)           // Swift's rules: .toNearestOrAwayFromZero, .down, .up, .towardZero, .toNearestOrEven
//     r ** -2, r.power(-2), r.reciprocal      // negative exponents: the reciprocal's power

final class BigRatValue: Swiftalk.HostValue, BigRatCarrier {
    let q: BigRat
    let type: Swiftalk.Value
    init(_ q: BigRat, type: Swiftalk.Value) { self.q = q; self.type = type }
    var bigRat: BigRat { q }
    var typeName: String { "BigRat" }
    func make(_ v: BigRat) -> Swiftalk.Value { .host(BigRatValue(v, type: type)) }

    /// A BigInt of the BigInt module, through the `BigInt` type in scope.
    static func bigInt(_ n: BigInt, for what: String) throws -> Swiftalk.Value {
        guard let t = Swiftalk.lookup("BigInt") else {
            throw Swiftalk.Error.type("\(what) is a BigInt — import from \"BigInt\" (the CLI preimports it)")
        }
        return try Swiftalk.call(t, [.string(n.description)])
    }

    // ---- parsing: "n/d", "-3", "0.75", "1.5e3", radix prefixes on integers ----
    static func integer(_ text: Substring) -> BigInt? {
        var s = text
        var negative = false
        if s.hasPrefix("-") { negative = true; s = s.dropFirst() } else if s.hasPrefix("+") { s = s.dropFirst() }
        var radix = 10
        if s.hasPrefix("0x") || s.hasPrefix("0X") { radix = 16; s = s.dropFirst(2) }
        else if s.hasPrefix("0o") || s.hasPrefix("0O") { radix = 8; s = s.dropFirst(2) }
        else if s.hasPrefix("0b") || s.hasPrefix("0B") { radix = 2; s = s.dropFirst(2) }
        if s.hasSuffix("n") { s = s.dropLast() }
        guard !s.isEmpty, let v = BigInt(s, radix: radix) else { return nil }
        return negative ? -v : v
    }
    static func parse(_ text: String) -> BigRat? {
        let s = Substring(text.filter { $0 != "_" && $0 != " " })
        if let slash = s.firstIndex(of: "/") {
            guard let n = integer(s[..<slash]), let d = integer(s[s.index(after: slash)...]), d != 0 else { return nil }
            return BigRat(n, d)
        }
        if let v = integer(s) { return BigRat(v) }
        // a decimal: sign, digits, an optional fraction, an optional exponent
        var rest = s
        var negative = false
        if rest.hasPrefix("-") { negative = true; rest = rest.dropFirst() } else if rest.hasPrefix("+") { rest = rest.dropFirst() }
        var digits = "", scale = 0, exponent = 0, sawDot = false, sawDigit = false
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if c.isASCII, c.isNumber { digits.append(c); sawDigit = true; if sawDot { scale += 1 } }
            else if c == ".", !sawDot { sawDot = true }
            else if c == "e" || c == "E" {
                guard let e = Int(rest[rest.index(after: i)...]) else { return nil }
                exponent = e
                break
            } else { return nil }
            i = rest.index(after: i)
        }
        guard sawDigit, let mantissa = BigInt(digits, radix: 10) else { return nil }
        let k = exponent - scale
        let ten = BigInt(10)
        let q = k >= 0 ? BigRat(mantissa * ten.power(k), 1) : BigRat(mantissa, ten.power(-k))
        return negative ? -q : q
    }

    private func rule(_ v: Swiftalk.Value) throws -> FloatingPointRoundingRule {
        guard case .string(let name) = v else { throw Swiftalk.Error.type("BigRat.rounded takes a rule: .toNearestOrAwayFromZero, .toNearestOrEven, .up, .down, .towardZero, .awayFromZero") }
        switch name {
        case "toNearestOrAwayFromZero": return .toNearestOrAwayFromZero
        case "toNearestOrEven": return .toNearestOrEven
        case "up": return .up
        case "down": return .down
        case "towardZero": return .towardZero
        case "awayFromZero": return .awayFromZero
        default: throw Swiftalk.Error.type("BigRat.rounded: unknown rule .\(name)")
        }
    }
    private func exponent(_ v: Swiftalk.Value, _ what: String) throws -> BigInt {
        switch v {
        case .int(let i): return BigInt(i)
        case .host(let h): if let c = h as? BigIntCarrier { return c.bigInt }; fallthrough
        default: throw Swiftalk.Error.type("\(what) takes an Int or BigInt exponent, not \(v.typeName)")
        }
    }
    private func raised(_ e: BigInt) throws -> BigRat {
        guard let n = Int(exactly: e.magnitude) else { throw Swiftalk.Error.type("BigRat.power: the exponent must fit an Int") }
        if e < 0 {
            guard !q.isZero else { throw Swiftalk.Error.zeroDivision }
            return BigRat(q.denominator.power(n), q.numerator.power(n))
        }
        return BigRat(q.numerator.power(n), q.denominator.power(n))
    }

    func member(_ name: String, args: [Swiftalk.Value], called: Bool) throws -> Swiftalk.Value? {
        switch (name, called) {
        case ("BigRat", true):  return .host(self)
        case ("Double", true):  return .double(q.toDouble())
        case ("BigInt", true):  return try BigRatValue.bigInt(q.rounded(.towardZero).numerator, for: "r.BigInt()")
        case ("Int", true):
            guard let i = Int64(exactly: q.rounded(.towardZero).numerator) else { throw Swiftalk.Error.overflow("\(sourceString(debug: false)) does not fit in an Int") }
            return .int(i)
        case ("String", true):
            guard let format = args.first else { return .string(sourceString(debug: false)) }
            guard args.count == 1, case .string(let f) = format else { throw Swiftalk.Error.type("BigRat.String() takes at most one format: .fraction or .mixed") }
            switch f {
            case "fraction": return .string("\(q.numerator)/\(q.denominator)")
            case "mixed":
                let (whole, part) = q.toMixed()
                if part.isZero { return .string(whole.description) }
                let frac = "\(part.magnitude.numerator)/\(part.denominator)"
                return .string(whole.isZero ? (q < 0 ? "-" : "") + frac : "\(whole) \(frac)")
            default: throw Swiftalk.Error.type("BigRat.String() takes .fraction or .mixed, not .\(f)")
            }
        case ("numerator", false):   return try BigRatValue.bigInt(q.numerator, for: "r.numerator")
        case ("denominator", false): return try BigRatValue.bigInt(q.denominator, for: "r.denominator")
        case ("isInteger", false):   return .bool(q.denominator == 1)
        case ("isZero", false):      return .bool(q.isZero)
        case ("magnitude", false):   return make(q.magnitude)
        case ("signum", false):      return .int(Int64(q.numerator.signum()))
        case ("reciprocal", false):
            guard !q.isZero else { throw Swiftalk.Error.zeroDivision }
            return make(BigRat(q.denominator, q.numerator))
        case ("rounded", true):
            guard args.count <= 1 else { throw Swiftalk.Error.type("BigRat.rounded() or .rounded(rule)") }
            return make(q.rounded(args.isEmpty ? .toNearestOrAwayFromZero : try rule(args[0])))
        case ("power", true):
            guard args.count == 1 else { throw Swiftalk.Error.type("BigRat.power(exponent) takes one Int or BigInt") }
            return make(try raised(try exponent(args[0], "BigRat.power")))
        default: return nil
        }
    }

    // ---- operators ----
    static let operators: Set<String> = ["infix:+", "infix:-", "infix:*", "infix:/", "infix:**", "infix:<", "prefix:-", "prefix:+"]
    func hasOperator(_ key: String) -> Bool { BigRatValue.operators.contains(key) }
    func operate(_ key: String, _ operands: [Swiftalk.Value]) throws -> Swiftalk.Value? {
        guard BigRatValue.operators.contains(key) else { return nil }
        let op = String(key.split(separator: ":", maxSplits: 1)[1])
        if key.hasPrefix("prefix") { return make(op == "-" ? -q : q) }
        guard operands.count == 2 else { return nil }
        if op == "**" {
            guard case .host(let h) = operands[0], let base = h as? BigRatValue else {
                throw Swiftalk.Error.type("'**' takes a BigRat base and an Int or BigInt exponent")
            }
            return base.make(try base.raised(try exponent(operands[1], "'**'")))
        }
        let sides = try operands.map { v -> BigRat in
            if case .host(let h) = v {
                if let r = h as? BigRatValue { return r.q }
                if h is BigIntCarrier { throw Swiftalk.Error.type("'\(op)' between BigRat and BigInt: convert first — BigRat(b), or r.BigInt()") }
            }
            switch v {
            case .int, .double, .byte:
                throw Swiftalk.Error.type("'\(op)' between BigRat and \(v.typeName): convert first — BigRat(x)")
            default:
                throw Swiftalk.Error.type("'\(op)' is not defined between \(operands[0].typeName) and \(operands[1].typeName)")
            }
        }
        let (a, b) = (sides[0], sides[1])
        switch op {
        case "+": return make(a + b)
        case "-": return make(a - b)
        case "*": return make(a * b)
        case "/":
            guard !b.isZero else { throw Swiftalk.Error.zeroDivision }
            return make(a / b)
        case "<": return .bool(a < b)
        default: return nil
        }
    }

    func isEqual(to other: any Swiftalk.HostValue) -> Bool { (other as? BigRatValue)?.q == q }
    func hash(into hasher: inout Hasher) { hasher.combine(q.numerator); hasher.combine(q.denominator) }
    /// `BigRat(1, 3)`: re-enters (§3d); an integer keeps its `1` denominator visible, so the type shows
    func sourceString(debug: Bool) -> String {
        let n = debug ? (q.numerator < 0 ? "-0x" : "+0x") + q.numerator.magnitude.toString(radix: 16) + "n" : q.numerator.description
        let d = debug ? "+0x" + q.denominator.toString(radix: 16) + "n" : q.denominator.description
        return "BigRat(\(n), \(d))"
    }
    func patternMatch(_ subject: Swiftalk.Value, binding: Bool) throws -> Swiftalk.Value? {
        guard case .host(let h) = subject, let r = h as? BigRatValue else {
            if binding { throw Swiftalk.Error.type("a BigRat case needs a BigRat subject, not \(subject.typeName)") }
            return nil
        }
        return r.q == q ? subject : nil
    }
}

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "BigRat")
    final class TypeBox { var value: Swiftalk.Value = .nil }
    let box = TypeBox()
    func integer(_ v: Swiftalk.Value, _ what: String) throws -> BigInt {
        switch v {
        case .int(let i): return BigInt(i)
        case .byte(let b): return BigInt(b)
        case .host(let h): if let c = h as? BigIntCarrier { return c.bigInt }; fallthrough
        default: throw Swiftalk.Error.type("\(what) takes Ints or BigInts, not \(v.typeName)")
        }
    }
    /// `BigRat(n, d)` from Ints or BigInts; `BigRat(x)` from an Int, a Byte,
    /// a BigInt, a Double (exactly), a String ("1/3", "0.75", "1e-2"), or a
    /// BigRat; `BigRat()` is 0.
    box.value = m.type("BigRat") { args in
        let make = { (v: BigRat) -> Swiftalk.Value in .host(BigRatValue(v, type: box.value)) }
        switch args.count {
        case 0: return make(BigRat(0))
        case 1:
            switch args[0] {
            case .int, .byte: return make(BigRat(try integer(args[0], "BigRat")))
            case .double(let d):
                guard d.isFinite else { throw Swiftalk.Error.type("BigRat(\(args[0].sourceString())): not a number a rational can hold") }
                return make(BigRat(d))
            case .string(let s):
                guard let v = BigRatValue.parse(s) else { throw Swiftalk.Error.type("BigRat(\"\(s)\"): not a rational — \"n/d\", an integer, or a decimal") }
                return make(v)
            case .host(let h):
                if let r = h as? BigRatValue { return .host(r) }
                if let c = h as? BigIntCarrier { return make(BigRat(c.bigInt)) }
                throw Swiftalk.Error.type("cannot convert \(args[0].typeName) to BigRat")
            default:
                throw Swiftalk.Error.type("cannot convert \(args[0].typeName) to BigRat")
            }
        case 2:
            let n = try integer(args[0], "BigRat(n, d)"), d = try integer(args[1], "BigRat(n, d)")
            guard d != 0 else { throw Swiftalk.Error.zeroDivision }
            return make(BigRat(n, d))
        default:
            throw Swiftalk.Error.type("BigRat(x) or BigRat(numerator, denominator)")
        }
    }
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
