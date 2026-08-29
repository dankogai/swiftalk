/// Types as constructor Functions, protocols as values, and the
/// conformance table (Design.md §10, rounds 25/26, implemented round 39).
///
/// The registry is a process-wide singleton: `42.type` must return the
/// very object bound to the global `Int`, so identity comparison
/// (`x.type == Int`) works — across every Interpreter alike.
enum Builtins {
    /// A home for builtin closures' lexical slot; never looked up.
    /// (nonisolated(unsafe): created once, never mutated afterward.)
    nonisolated(unsafe) static let emptyEnvironment = Environment()

    private static func type(_ name: String,
                             _ construct: @escaping ([Value]) throws -> Value) -> FunctionObject {
        FunctionObject(parameters: [], body: [], closure: emptyEnvironment,
                       builtin: construct, role: .type(name))
    }

    private static func protocolObject(_ name: String) -> FunctionObject {
        FunctionObject(parameters: [], body: [], closure: emptyEnvironment,
                       builtin: { _ in
                           throw SwiftalkError.type("\(name) is a protocol, not a constructor")
                       },
                       role: .protocol(name))
    }

    /// The type constructors: `Type()` gives the Swift-style default,
    /// `Type(x)` converts — identity from the same type, failable (nil)
    /// where the *value* may not convert, a type error where the source
    /// *type* never converts (§3d: the same operation as `x.Type()`,
    /// spelled from the other end).
    nonisolated(unsafe) static let types: [String: FunctionObject] = [
        "Nil": type("Nil") { args in
            switch args.first {
            case nil, .nil: return .nil
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Nil")
            }
        },
        "Bool": type("Bool") { args in
            switch args.first {
            case nil:              return .bool(false)
            case .bool(let b)?:    return .bool(b)
            case .string(let s)?:  return s == "true" ? .bool(true) : s == "false" ? .bool(false) : .nil
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Bool")
            }
        },
        "Int": type("Int") { args in
            switch args.first {
            case nil:             return .int(0)
            case .int(let i)?:    return .int(i)
            case .double(let d)?: // truncation toward zero, as in Swift; nil if unrepresentable
                guard let i = Int64(exactly: d.rounded(.towardZero)) else { return .nil }
                return .int(i)
            case .string(let s)?: return parseInt(s).map(Value.int) ?? .nil
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Int")
            }
        },
        "Double": type("Double") { args in
            switch args.first {
            case nil:             return .double(0)
            case .double(let d)?: return .double(d)
            case .int(let i)?:    return .double(Double(i))
            case .string(let s)?: // Swift's parser accepts hex floats: Double("0x1.8p0") == 1.5
                return Double(s).map(Value.double) ?? .nil
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Double")
            }
        },
        "String": type("String") { args in
            // String(x) is x's description (§3d): a String is itself,
            // everything else its source form — same as x.String() except
            // the identity case, which is a copy, not a quoting.
            switch args.first {
            case nil:     return .string("")
            case let v?:  return .string(displayString(v))
            }
        },
        "Array": type("Array") { args in
            switch args.first {
            case nil:            return .array([])
            case .array(let a)?: return .array(a)
            case let v?:         return .array(Array(try elements(of: v)))  // any Sequence
            }
        },
        "Dictionary": type("Dictionary") { args in
            switch args.first {
            case nil:                 return .dictionary([:])
            case .dictionary(let d)?: return .dictionary(d)
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Dictionary")
            }
        },
        "Range": type("Range") { args in
            switch args.first {
            case .range(let l, let u, let c)?: return .range(from: l, to: u, closed: c)
            case nil: throw SwiftalkError.type("construct a Range with its literal: a...b or a..<b")
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Range")
            }
        },
        "Function": type("Function") { args in
            switch args.first {
            case .function(let f)?: return .function(f)
            case nil: throw SwiftalkError.type("there is no default Function")
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Function")
            }
        },
    ]

    /// The protocol roster (§10): coarse-grained, exactly four.
    nonisolated(unsafe) static let protocols: [String: FunctionObject] = [
        "Sequence":   protocolObject("Sequence"),
        "Equatable":  protocolObject("Equatable"),
        "Hashable":   protocolObject("Hashable"),
        "Comparable": protocolObject("Comparable"),
    ]

    private static let allTypeNames: Set<String> =
        ["Nil", "Bool", "Int", "Double", "String", "Array", "Dictionary", "Range", "Function"]

    /// Who conforms to what (§10, rounds 26/38): built-ins conform
    /// natively — everything is Equatable and Hashable (all values are
    /// dictionary keys), Comparable is Int/Double/String, Sequence is
    /// the four iterables.
    static let conformance: [String: Set<String>] = [
        "Sequence":   ["String", "Array", "Dictionary", "Range"],
        "Equatable":  allTypeNames,
        "Hashable":   allTypeNames,
        "Comparable": ["Int", "Double", "String"],
    ]

    /// Int-from-String, accepting everything the lexer does: optional
    /// sign, 0x/0o/0b prefixes, `_` separators — so debug hex output
    /// re-enters via Int(s) too.
    static func parseInt(_ input: String) -> Int64? {
        var s = Substring(input.filter { $0 != "_" })
        var negative = false
        if s.first == "-" || s.first == "+" {
            negative = s.first == "-"
            s = s.dropFirst()
        }
        var radix = 10
        if s.hasPrefix("0x") { radix = 16; s = s.dropFirst(2) }
        else if s.hasPrefix("0o") { radix = 8; s = s.dropFirst(2) }
        else if s.hasPrefix("0b") { radix = 2; s = s.dropFirst(2) }
        guard !s.isEmpty, let magnitude = UInt64(s, radix: radix) else { return nil }
        if negative {
            guard magnitude <= UInt64(Int64.max) + 1 else { return nil }
            return magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude)
        }
        guard magnitude <= UInt64(Int64.max) else { return nil }
        return Int64(magnitude)
    }
}
