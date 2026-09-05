#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `Double.pi`, `Double.sqrt(x)`, … — libm and JS's `Math`, as static
/// members of `Double` (round 108). Constants are read bare; functions
/// are called, or taken uncalled as Function values (`xs.map(Double.sqrt)`).
/// Int arguments are promoted — the type is named in the call — and every
/// result is a Double, except where the answer is an Int (`ilogb`), a
/// Bool (`isNaN`…), or a labeled tuple (`modf`, `frexp`, `remquo`).
enum DoubleMath {
    static let constants: [String: Double] = [
        "pi": .pi, "tau": 2 * .pi, "e": M_E,
        "ln2": M_LN2, "ln10": M_LN10, "log2e": M_LOG2E, "log10e": M_LOG10E,
        "sqrt2": 2.0.squareRoot(), "sqrtHalf": 0.5.squareRoot(),
        "infinity": .infinity, "nan": .nan,
        "greatestFiniteMagnitude": .greatestFiniteMagnitude,
        "leastNormalMagnitude": .leastNormalMagnitude,
        "leastNonzeroMagnitude": .leastNonzeroMagnitude,
        "ulpOfOne": .ulpOfOne,
        "zero": 0, "radix": 2,                                          // round 113
        "exponentBitCount": Double(Double.exponentBitCount),
        "significandBitCount": Double(Double.significandBitCount),
    ]

    nonisolated(unsafe) static let unary: [String: (Double) -> Double] = [
        "abs": { Swift.abs($0) }, "sqrt": { $0.squareRoot() }, "cbrt": { cbrt($0) },
        "exp": { exp($0) }, "exp2": { exp2($0) }, "expm1": { expm1($0) },
        "log": { log($0) }, "log2": { log2($0) }, "log10": { log10($0) }, "log1p": { log1p($0) },
        "logb": { logb($0) },
        "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "sinh": { sinh($0) }, "cosh": { cosh($0) }, "tanh": { tanh($0) },
        "asinh": { asinh($0) }, "acosh": { acosh($0) }, "atanh": { atanh($0) },
        "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) }, "trunc": { $0.rounded(.towardZero) },
        "round": { $0.rounded() },                     // half away from zero — C's, Swift's; JS rounds half up
        "rint": { $0.rounded(.toNearestOrEven) }, "nearbyint": { $0.rounded(.toNearestOrEven) },
        "sign": { $0.isNaN ? .nan : $0 > 0 ? 1 : $0 < 0 ? -1 : $0 },   // JS's: ±0 come back as they are
        "erf": { erf($0) }, "erfc": { erfc($0) },
        "tgamma": { tgamma($0) }, "gamma": { tgamma($0) }, "lgamma": { lgamma($0) },
        "j0": { j0($0) }, "j1": { j1($0) }, "y0": { y0($0) }, "y1": { y1($0) },
        "fround": { Double(Float($0)) },
    ]

    nonisolated(unsafe) static let binary: [String: (Double, Double) -> Double] = [
        "pow": { pow($0, $1) }, "atan2": { atan2($0, $1) },
        "fmod": { fmod($0, $1) }, "remainder": { remainder($0, $1) },
        "fdim": { fdim($0, $1) }, "fmax": { fmax($0, $1) }, "fmin": { fmin($0, $1) },
        "copysign": { copysign($0, $1) }, "nextafter": { nextafter($0, $1) },
    ]

    nonisolated(unsafe) static let predicates: [String: (Double) -> Bool] = [
        "isNaN": { $0.isNaN }, "isFinite": { $0.isFinite }, "isInfinite": { $0.isInfinite },
        "isZero": { $0.isZero }, "isNormal": { $0.isNormal }, "isSubnormal": { $0.isSubnormal },
    ]

    /// The names that are functions (for the uncalled, Function-valued form).
    static let functions: Set<String> = Set(unary.keys).union(binary.keys).union(predicates.keys)
        .union(["max", "min", "hypot", "random", "fma", "ldexp", "scalbn", "ilogb", "jn", "yn",
                "modf", "frexp", "remquo"])

    /// nil when `name` is not a math member — the caller falls through.
    static func member(_ name: String, args: [(label: String?, value: Value)], called: Bool) throws -> Value? {
        if let c = constants[name] {
            guard !called else { throw SwiftalkError.type("Double.\(name) is a constant, not a function") }
            return .double(c)
        }
        guard functions.contains(name) else { return nil }
        if let label = args.compactMap(\.label).first {
            throw SwiftalkError.type("Double.\(name) takes no argument label '\(label)'")
        }
        let values = args.map(\.value)
        if !called {
            // the Function-valued form: `xs.map(Double.sqrt)`
            return .function(FunctionObject(parameters: [], body: [], closure: Builtins.emptyEnvironment,
                                            builtin: { try apply(name, $0) }))
        }
        return try apply(name, values)
    }

    private static func number(_ v: Value, _ name: String) throws -> Double {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default: throw SwiftalkError.type("Double.\(name) takes numbers, not a \(v.typeName)")
        }
    }

    private static func apply(_ name: String, _ args: [Value]) throws -> Value {
        func arity(_ n: Int) throws -> [Double] {
            guard args.count == n else {
                throw SwiftalkError.type("Double.\(name) takes \(n) argument\(n == 1 ? "" : "s"), got \(args.count)")
            }
            return try args.map { try number($0, name) }
        }
        if let f = unary[name]      { return .double(f(try arity(1)[0])) }
        if let f = binary[name]     { let a = try arity(2); return .double(f(a[0], a[1])) }
        if let p = predicates[name] { return .bool(p(try arity(1)[0])) }
        switch name {
        case "max", "min":
            guard !args.isEmpty else { throw SwiftalkError.type("Double.\(name) takes at least one number") }
            let xs = try args.map { try number($0, name) }
            return .double(name == "max" ? xs.reduce(-.infinity, { Swift.max($0, $1) })
                                         : xs.reduce(.infinity, { Swift.min($0, $1) }))
        case "hypot":
            let xs = try args.map { try number($0, name) }
            return .double(xs.reduce(0.0) { hypot($0, $1) })
        case "random":
            // random() in [0, 1); random(max) in [0, max); random(min, max)
            // in [min, max) — round 112: Range is Int-only, so the bounds
            // are arguments. Finite, non-empty.
            let bounds = try args.map { try number($0, name) }
            let (lo, hi): (Double, Double)
            switch bounds.count {
            case 0: (lo, hi) = (0, 1)
            case 1: (lo, hi) = (0, bounds[0])
            case 2: (lo, hi) = (bounds[0], bounds[1])
            default: throw SwiftalkError.type("Double.random() / random(max) / random(min, max)")
            }
            guard lo.isFinite, hi.isFinite, lo < hi else {
                throw SwiftalkError.type("Double.random needs finite bounds with min < max, got \(lo) and \(hi)")
            }
            return .double(Double.random(in: lo..<hi))
        case "fma":
            let a = try arity(3); return .double(fma(a[0], a[1], a[2]))
        case "ldexp", "scalbn":
            guard args.count == 2, case .int(let n) = args[1] else {
                throw SwiftalkError.type("Double.\(name)(x, n) takes a number and an Int")
            }
            return .double(scalbn(try number(args[0], name), Int(clamping: n)))
        case "ilogb":
            return .int(Int64(ilogb(try arity(1)[0])))
        case "jn", "yn":
            guard args.count == 2, case .int(let n) = args[0] else {
                throw SwiftalkError.type("Double.\(name)(n, x) takes an Int order and a number")
            }
            let x = try number(args[1], name)
            return .double(name == "jn" ? jn(Int32(clamping: n), x) : yn(Int32(clamping: n), x))
        case "modf":
            let x = try arity(1)[0]
            let whole = x.rounded(.towardZero)
            return .tuple([.double(whole), .double(x - whole)], labels: ["integer", "fraction"])
        case "frexp":
            let x = try arity(1)[0]
            let (fraction, exponent) = frexp(x)
            return .tuple([.double(fraction), .int(Int64(exponent))], labels: ["fraction", "exponent"])
        case "remquo":
            let a = try arity(2)
            let (rem, quo) = remquo(a[0], a[1])
            return .tuple([.double(rem), .int(Int64(quo))], labels: ["remainder", "quotient"])
        default:
            throw SwiftalkError.unknownMember("Double.\(name)")
        }
    }
}

/// Swift's static properties on Int (round 113): read bare, never called.
enum IntStatics {
    nonisolated(unsafe) static let values: [String: Value] = [
        "min": .int(Int64.min), "max": .int(Int64.max),
        "bitWidth": .int(64), "zero": .int(0), "isSigned": .bool(true),
    ]
}

/// `Int.random(in: range)` (round 109): Swift's, on swiftalk's Int-only
/// Range — closed or half-open, never empty, never unbounded.
enum IntRandom {
    static func call(_ args: [(label: String?, value: Value)]) throws -> Value {
        guard args.count == 1, args[0].label == nil || args[0].label == "in",
              case .range(let lower, let upper, let closed) = args[0].value else {
            throw SwiftalkError.type("Int.random(in:) takes one Range: Int.random(in: 1...6)")
        }
        guard let upper else {
            throw SwiftalkError.type("Int.random(in:) needs a bounded Range — \(lower)... has no upper bound")
        }
        if closed {
            return .int(Int64.random(in: lower...upper))
        }
        guard lower < upper else {
            throw SwiftalkError.type("Int.random(in:) needs a non-empty Range — \(lower)..<\(upper) is empty")
        }
        return .int(Int64.random(in: lower..<upper))
    }
}
