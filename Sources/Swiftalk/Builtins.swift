#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

    /// `Result` (round 51, §8): a built-in enum riding round 45's
    /// machinery — switch, case accessors (`r.success` → value-or-nil),
    /// equality, and source form all come free. Payloads are untyped:
    /// a failure carries any value (§8's mixed-error-types answer until
    /// typed errors are designed).
    nonisolated(unsafe) static let resultType: EnumType = {
        let et = EnumType(name: "Result",
                          caseOrder: ["success", "failure"],
                          cases: ["success": [(label: nil, typeName: nil)],
                                  "failure": [(label: nil, typeName: nil)]])
        let constructor = FunctionObject(
            parameters: [], body: [], closure: emptyEnvironment,
            builtin: { _ in
                throw SwiftalkError.type(
                    "construct a Result via Result.success(v) or Result.failure(e)")
            },
            role: .enumType(et))
        et.constructor = constructor
        return et
    }()

    /// The `.todo` placeholder Function (round 44).
    nonisolated(unsafe) static let todo = FunctionObject(
        parameters: [], body: [], closure: emptyEnvironment,
        builtin: { _ in
            throw SwiftalkError.type(
                "this Function is .todo — assign an implementation before calling it")
        },
        role: .todo)

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
            case .date(let t)?:   return .double(t)   // a Date IS its epoch (round 50)
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
            case let v?:         return .array(try collect(v))  // any Sequence
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
        "Data": type("Data") { args in
            switch args.first {
            case nil:              return .data([])
            case .data(let b)?:    return .data(b)
            case .string(let s)?:  return .data(Array(s.utf8))   // str.Data() — infallible (§3d)
            case .array(let a)?:
                // Data([255, 1]) — the source form; a non-byte is nil (failable)
                var bytes: [UInt8] = []
                for v in a {
                    guard case .int(let i) = v, let byte = UInt8(exactly: i) else { return .nil }
                    bytes.append(byte)
                }
                return .data(bytes)
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Data")
            }
        },
        "Task": type("Task") { args in
            // Task { ... } / Task(f) — spawn (round 53, §12). Eager,
            // the JS way: the body runs at once, until it suspends or
            // completes; the spawner resumes next. `async { ... }` is
            // parse-level sugar for exactly this call.
            guard args.count == 1, case .function(let f) = args[0] else {
                throw SwiftalkError.type("Task { ... } spawns a Function as a concurrent task")
            }
            guard f.builtin == nil else {
                throw SwiftalkError.type("Task(f): cannot spawn a builtin Function")
            }
            guard f.parameters.isEmpty else {
                throw SwiftalkError.type(
                    "Task(f): a task body declares no parameters — nothing is passed in")
            }
            guard let ctx = Scheduler.current else {
                throw SwiftalkError.type(
                    "Task { ... } inside a Sequence coroutine body is not (yet) supported")
            }
            return try ctx.scheduler.spawn(f, from: ctx)
        },
        "Date": type("Date") { args in
            switch args.first {
            case nil:
                // Date() is now — wall clock, Foundation-free.
                var ts = timespec()
                clock_gettime(CLOCK_REALTIME, &ts)
                return .date(Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9)
            case .date(let t)?:    return .date(t)
            case .double(let t)?:  return .date(t)
            case .int(let t)?:     return .date(Double(t))
            case let v?: throw SwiftalkError.type("cannot convert \(v.typeName) to Date")
            }
        },
    ]

    /// The protocol roster (§10): coarse-grained, exactly four.
    /// `Sequence` alone also constructs (round 41): a lazy generated
    /// sequence — `Sequence(initialState) { next }`.
    nonisolated(unsafe) static let protocols: [String: FunctionObject] = [
        "Sequence": FunctionObject(
            parameters: [], body: [], closure: emptyEnvironment,
            builtin: { args in
                // Sequence(f) — the coroutine wrap (round 52): pulls
                // resume f, `yield`s are the elements, returning ends it.
                if args.count == 1, case .function(let f) = args[0] {
                    guard f.builtin == nil else {
                        throw SwiftalkError.type(
                            "Sequence(f): cannot wrap a builtin Function as a coroutine")
                    }
                    guard f.parameters.isEmpty else {
                        throw SwiftalkError.type(
                            "Sequence(f): a coroutine body declares no parameters — nothing is passed in on resume")
                    }
                    return .sequence(SequenceObject(kind: .coroutine(body: f)))
                }
                guard args.count == 2,
                      case .array(let initial) = args[0],
                      case .function(let next) = args[1] else {
                    throw SwiftalkError.type(
                        "Sequence(f) wraps a yielding Function; Sequence(initialState) { next } generates")
                }
                return .sequence(SequenceObject(kind: .generator(initial: initial, next: next)))
            },
            role: .protocol("Sequence")),
        "Equatable":  protocolObject("Equatable"),
        "Hashable":   protocolObject("Hashable"),
        "Comparable": protocolObject("Comparable"),
    ]

    private static let allTypeNames: Set<String> =
        ["Nil", "Bool", "Int", "Double", "String", "Array", "Dictionary",
         "Range", "Function", "Sequence", "Data", "Date", "Task"]

    /// Who conforms to what (§10, rounds 26/38/41): built-ins conform
    /// natively — everything is Equatable and Hashable (all values are
    /// dictionary keys), Comparable is Int/Double/String, Sequence is
    /// the iterables (lazy Sequences included).
    static let conformance: [String: Set<String>] = [
        "Sequence":   ["String", "Array", "Dictionary", "Range", "Sequence"],
        "Equatable":  allTypeNames,
        "Hashable":   allTypeNames,
        "Comparable": ["Int", "Double", "String", "Date"],
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
