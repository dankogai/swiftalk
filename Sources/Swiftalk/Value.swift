/// The swiftalk namespace: the entire public embedding API lives here —
/// `Swiftalk.eval(...)`, `Swiftalk.Interpreter`, `Swiftalk.Value`,
/// `Swiftalk.Error` — so importing the library claims exactly one
/// top-level name.
public enum Swiftalk {}

extension Swiftalk {
    /// A swiftalk runtime value, covering the SION-complete primitive
    /// space plus `Function` (Design.md §3b/§3c/§2.4). `Data` and `Date`
    /// join in later milestones.
    public enum Value: Hashable {
        case `nil`
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        indirect case array([Value])
        indirect case dictionary([Value: Value])
        case function(FunctionObject)
        /// `Range<I>` (round 38): lazy, first-class, integer-only —
        /// `I` is Int today, BigInt someday, never Double (a deliberate
        /// divergence from Swift's versatile Range). `closed` is
        /// `a...b` vs `a..<b`.
        case range(from: Int64, to: Int64, closed: Bool)
    }

    /// A function value: `{}` is the only function form (Design.md §2.4).
    /// Reference identity is its equality — `Function` is one collective
    /// type and functions compare as themselves, not by structure.
    /// Built-ins (`print`, ...) are the same type with a Swift closure
    /// for a body — the stdlib arrives as ordinary Function values.
    public final class FunctionObject: Hashable {
        let parameters: [String]      // empty means variadic (round 14)
        let body: [Stmt]
        let closure: Environment      // lexical capture
        let builtin: (([Value]) throws -> Value)?

        init(parameters: [String], body: [Stmt], closure: Environment,
             builtin: (([Value]) throws -> Value)? = nil) {
            self.parameters = parameters
            self.body = body
            self.closure = closure
            self.builtin = builtin
        }

        public static func == (lhs: FunctionObject, rhs: FunctionObject) -> Bool {
            lhs === rhs
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}

// Internal shorthands — implementation files (and @testable tests) keep
// the unqualified spellings; only the public surface is namespaced.
typealias Value = Swiftalk.Value
typealias FunctionObject = Swiftalk.FunctionObject

extension Value {
    /// The swiftalk type name reported by `.type` (Design.md §3).
    /// Once types become constructor Functions (§10) this will return a
    /// callable; for milestone 0 it is a name.
    public var typeName: String {
        switch self {
        case .nil:        return "Nil"
        case .bool:       return "Bool"
        case .int:        return "Int"
        case .double:     return "Double"
        case .string:     return "String"
        case .array:      return "Array"
        case .dictionary: return "Dictionary"
        case .function:   return "Function"
        case .range:      return "Range"
        }
    }

    /// swiftalk's `.String()`: source form obeying the round-trip law
    /// `eval(x.String()) == x` (Design.md §3d). With `debug: true` it is
    /// `.debugDescription` (round 37): numbers render hexadecimal — Int
    /// as `0xff`, Double as hex-float `0x1.fep7` — for the programmer's
    /// sake, recursively through collections.
    public func sourceString(debug: Bool = false) -> String {
        switch self {
        case .nil:
            return "nil"
        case .bool(let b):
            return b ? "true" : "false"
        case .int(let i):
            return debug ? (i < 0 ? "-0x" : "0x") + String(i.magnitude, radix: 16)
                         : String(i)
        case .double(let d):
            // Swift's Double description is the shortest string that
            // round-trips, e.g. (0.1 + 0.2) -> "0.30000000000000004".
            return debug ? Value.hexFloat(d) : String(d)
        case .string(let s):
            return Value.quote(s)
        case .array(let a):
            return "[" + a.map { $0.sourceString(debug: debug) }.joined(separator: ", ") + "]"
        case .function(let f):
            // Function.String() as source text is OPEN (Design.md §3d);
            // until then, a non-round-tripping placeholder.
            let params = f.parameters.isEmpty ? "" : f.parameters.joined(separator: ", ") + " in "
            return "{ \(params)... }"
        case .range(let lower, let upper, let closed):
            // Literal syntax — round-trips through the lexer (§3d).
            return Value.int(lower).sourceString(debug: debug)
                + (closed ? "..." : "..<")
                + Value.int(upper).sourceString(debug: debug)
        case .dictionary(let d):
            if d.isEmpty { return "[:]" }
            // Deterministic output: order entries by their key's source form.
            let body = d
                .map { (key: $0.key.sourceString(debug: debug), value: $0.value.sourceString(debug: debug)) }
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            return "[" + body + "]"
        }
    }

    /// Swift-style hex-float notation (`0x1.fep7`), the Double
    /// `.debugDescription` of round 37. (The lexer does not parse
    /// hex-float literals yet — that half of the §3d round trip is OPEN.)
    static func hexFloat(_ d: Double) -> String {
        if d.isNaN { return "nan" }
        if d.isInfinite { return d < 0 ? "-inf" : "inf" }
        if d == 0 { return d.sign == .minus ? "-0x0p0" : "0x0p0" }
        let m = abs(d)
        guard m.isNormal else { return String(d) }   // subnormals: decimal fallback
        var hex = String(m.significandBitPattern, radix: 16)
        hex = String(repeating: "0", count: 13 - hex.count) + hex
        while hex.hasSuffix("0") { hex.removeLast() }
        let frac = hex.isEmpty ? "" : "." + hex
        return "\(d < 0 ? "-" : "")0x1\(frac)p\(m.exponent)"
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"":     out += "\\\""
            case "\\":     out += "\\\\"
            case "\n":     out += "\\n"
            case "\r":     out += "\\r"
            case "\t":     out += "\\t"
            case "\0":     out += "\\0"
            case let c where c.value < 0x20:
                out += "\\u{\(String(c.value, radix: 16))}"
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

extension Value: CustomStringConvertible {
    public var description: String { sourceString() }
}
