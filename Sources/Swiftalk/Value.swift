/// A swiftalk runtime value, covering the SION-complete primitive space
/// plus `Function` (Design.md §3b/§3c/§2.4). `Data` and `Date` join in
/// later milestones.
public enum Value: Hashable {
    case `nil`
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    indirect case array([Value])
    indirect case dictionary([Value: Value])
    case function(FunctionObject)
}

/// A function value: `{}` is the only function form (Design.md §2.4).
/// Reference identity is its equality — `Function` is one collective
/// type and functions compare as themselves, not by structure.
public final class FunctionObject: Hashable {
    let parameters: [String]      // empty means variadic (round 14)
    let body: [Stmt]
    let closure: Environment      // lexical capture

    init(parameters: [String], body: [Stmt], closure: Environment) {
        self.parameters = parameters
        self.body = body
        self.closure = closure
    }

    public static func == (lhs: FunctionObject, rhs: FunctionObject) -> Bool {
        lhs === rhs
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

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
        }
    }

    /// swiftalk's `.String()`: source form obeying the round-trip law
    /// `eval(x.String()) == x` (Design.md §3d).
    public func sourceString() -> String {
        switch self {
        case .nil:
            return "nil"
        case .bool(let b):
            return b ? "true" : "false"
        case .int(let i):
            return String(i)
        case .double(let d):
            // Swift's Double description is the shortest string that
            // round-trips, e.g. (0.1 + 0.2) -> "0.30000000000000004".
            return String(d)
        case .string(let s):
            return Value.quote(s)
        case .array(let a):
            return "[" + a.map { $0.sourceString() }.joined(separator: ", ") + "]"
        case .function(let f):
            // Function.String() as source text is OPEN (Design.md §3d);
            // until then, a non-round-tripping placeholder.
            let params = f.parameters.isEmpty ? "" : f.parameters.joined(separator: ", ") + " in "
            return "{ \(params)... }"
        case .dictionary(let d):
            if d.isEmpty { return "[:]" }
            // Deterministic output: order entries by their key's source form.
            let body = d
                .map { (key: $0.key.sourceString(), value: $0.value.sourceString()) }
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            return "[" + body + "]"
        }
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
