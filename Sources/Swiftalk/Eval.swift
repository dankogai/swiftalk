/// Milestone 0: `eval()` — source string in, value out (Design.md §13).
/// One-shot: bindings do not survive the call. For a persistent
/// environment (the REPL's engine), use `Interpreter`.
public func eval(_ source: String) throws -> Value {
    try Interpreter().eval(source)
}

/// A swiftalk interpreter with a persistent global environment:
/// bindings made in one `eval` call are visible to the next.
public final class Interpreter {
    private var environment = Environment()
    private let relaxed: Bool

    /// `relaxed` is REPL mode (Design.md §2.2): assignment to an
    /// undeclared name implicitly declares a `var` — still type-locked
    /// from then on. File mode (the default) rejects it.
    public init(relaxed: Bool = false) {
        self.relaxed = relaxed
    }

    /// Evaluates a program (statements separated by newlines or `;`)
    /// and returns the value of its last statement.
    public func eval(_ source: String) throws -> Value {
        var lexer = Lexer(source)
        var parser = Parser(try lexer.tokenize())
        let program = try parser.parseProgram()
        var last = Value.nil
        for statement in program {
            last = try execute(statement, in: environment, relaxed: relaxed)
        }
        return last
    }
}

/// True when `source` is a syntactically incomplete *prefix* — open
/// brackets awaiting their close — so a REPL should read more lines
/// rather than report an error. Anything else (complete or genuinely
/// malformed) returns false.
public func needsMoreInput(_ source: String) -> Bool {
    var lexer = Lexer(source)
    guard let tokens = try? lexer.tokenize() else { return false }
    var depth = 0
    for token in tokens {
        switch token {
        case .punct("["), .punct("("): depth += 1
        case .punct("]"), .punct(")"): depth -= 1
        default: break
        }
    }
    return depth > 0
}

/// A binding: its mutability, its type lock (Design.md §3), and its value.
/// The lock is fixed at declaration — from the annotation if written,
/// inferred from the initializer otherwise — and every later assignment
/// must satisfy it.
struct Binding {
    let mutable: Bool
    let lock: TypeAnnotation
    var value: Value
}

final class Environment {
    private var bindings: [String: Binding] = [:]

    func declare(_ name: String, _ binding: Binding) throws {
        guard bindings[name] == nil else {
            throw SwiftalkError.type("redeclaration of '\(name)'")
        }
        bindings[name] = binding
    }

    func assign(_ name: String, _ value: Value) throws {
        guard var binding = bindings[name] else {
            throw SwiftalkError.type(
                "cannot assign to undeclared '\(name)' — declare it with let or var")
        }
        guard binding.mutable else {
            throw SwiftalkError.type("cannot assign to let constant '\(name)'")
        }
        try check(value, against: binding.lock, for: name)
        binding.value = value
        bindings[name] = binding
    }

    func has(_ name: String) -> Bool {
        bindings[name] != nil
    }

    func lookup(_ name: String) throws -> Value {
        guard let binding = bindings[name] else {
            throw SwiftalkError.type("undefined variable '\(name)'")
        }
        return binding.value
    }

    /// The type-lock check (§3, §3a): the value's runtime type must match
    /// the lock, or be `nil` where the lock is optional (`Int?` is the flat
    /// union Int-or-nil, not a wrapper).
    func check(_ value: Value, against lock: TypeAnnotation, for name: String) throws {
        if case .nil = value {
            guard lock.optional || lock.name == "Nil" else {
                throw SwiftalkError.type(
                    "cannot assign nil to '\(name)' of type \(lock.name) — declare it \(lock.name)?")
            }
            return
        }
        guard value.typeName == lock.name else {
            throw SwiftalkError.type(
                "cannot assign \(value.typeName) to '\(name)' of type \(lock.name)\(lock.optional ? "?" : "")")
        }
    }
}

private let knownTypeNames: Set<String> =
    ["Nil", "Bool", "Int", "Double", "String", "Array", "Dictionary"]

func execute(_ statement: Stmt, in env: Environment, relaxed: Bool = false) throws -> Value {
    switch statement {
    case .declaration(let mutable, let name, let annotation, let initializer):
        let value = try evaluate(initializer, in: env)
        let lock: TypeAnnotation
        if let annotation {
            guard knownTypeNames.contains(annotation.name) else {
                throw SwiftalkError.type("unknown type '\(annotation.name)'")
            }
            lock = annotation
        } else {
            // Inference locks to the initializer's runtime type. Bare
            // `var x = nil` has nothing to infer and is rejected (§3a).
            guard value != .nil else {
                throw SwiftalkError.type(
                    "cannot infer a type for '\(name)' from nil — annotate it, e.g. \(mutable ? "var" : "let") \(name): Int? = nil")
            }
            lock = TypeAnnotation(name: value.typeName, optional: false)
        }
        try env.check(value, against: lock, for: name)
        try env.declare(name, Binding(mutable: mutable, lock: lock, value: value))
        return value
    case .assignment(let name, let expr):
        let value = try evaluate(expr, in: env)
        if relaxed && !env.has(name) {
            // REPL mode (§2.2): bare `x = 1` implicitly declares a var —
            // type-locked from here on, like any other binding.
            guard value != .nil else {
                throw SwiftalkError.type(
                    "cannot infer a type for '\(name)' from nil — annotate it, e.g. var \(name): Int? = nil")
            }
            try env.declare(name, Binding(
                mutable: true,
                lock: TypeAnnotation(name: value.typeName, optional: false),
                value: value))
            return value
        }
        try env.assign(name, value)
        return value
    case .expression(let expr):
        return try evaluate(expr, in: env)
    }
}

func evaluate(_ expr: Expr, in env: Environment) throws -> Value {
    switch expr {
    case .literal(let v):
        return v
    case .variable(let name):
        return try env.lookup(name)
    case .array(let elements):
        return .array(try elements.map { try evaluate($0, in: env) })
    case .dictionary(let pairs):
        var dict: [Value: Value] = [:]
        for (k, v) in pairs {
            dict[try evaluate(k, in: env)] = try evaluate(v, in: env)
        }
        return .dictionary(dict)
    case .unaryMinus(let e):
        switch try evaluate(e, in: env) {
        case .int(let i):
            guard i != Int64.min else {
                throw SwiftalkError.overflow("negating \(i)")
            }
            return .int(-i)
        case .double(let d):
            return .double(-d)
        case let v:
            throw SwiftalkError.type("cannot negate \(v.typeName)")
        }
    case .binary(let op, let lhs, let rhs):
        return try binary(op, try evaluate(lhs, in: env), try evaluate(rhs, in: env))
    case .method(let receiver, let name, let args, let called):
        return try method(on: try evaluate(receiver, in: env), name: name,
                          args: try args.map { try evaluate($0, in: env) }, called: called)
    }
}

/// Same-type arithmetic only (Design.md §3): `1 + 1.5` is a type error,
/// Int overflow traps (§3b), and `+` concatenates Strings and Arrays.
private func binary(_ op: Character, _ lhs: Value, _ rhs: Value) throws -> Value {
    switch (lhs, rhs) {
    case (.int(let a), .int(let b)):
        let (result, overflow): (Int64, Bool) = switch op {
        case "+": a.addingReportingOverflow(b)
        case "-": a.subtractingReportingOverflow(b)
        case "*": a.multipliedReportingOverflow(by: b)
        case "/":
            b == 0 ? (0, false) : a.dividedReportingOverflow(by: b)
        default: fatalError("unreachable operator \(op)")
        }
        if op == "/" && b == 0 { throw SwiftalkError.zeroDivision }
        guard !overflow else {
            throw SwiftalkError.overflow("\(a) \(op) \(b)")
        }
        return .int(result)
    case (.double(let a), .double(let b)):
        switch op {
        case "+": return .double(a + b)
        case "-": return .double(a - b)
        case "*": return .double(a * b)
        case "/": return .double(a / b)
        default: fatalError("unreachable operator \(op)")
        }
    case (.string(let a), .string(let b)) where op == "+":
        return .string(a + b)
    case (.array(let a), .array(let b)) where op == "+":
        return .array(a + b)
    default:
        throw SwiftalkError.type(
            "'\(op)' is not defined between \(lhs.typeName) and \(rhs.typeName)")
    }
}

/// Milestone 0 methods: just enough for `eval()` — `.String()` (the
/// round-trip law, §3d) and the `.type` property (§3, as a name for now).
private func method(on receiver: Value, name: String, args: [Value], called: Bool) throws -> Value {
    switch (name, called) {
    case ("String", true):
        guard args.isEmpty else {
            throw SwiftalkError.type(".String() format arguments are a later milestone")
        }
        return .string(receiver.sourceString())
    case ("type", false):
        // Types will become constructor Functions (§10); until Function
        // lands, .type evaluates to the type's name.
        return .string(receiver.typeName)
    default:
        throw SwiftalkError.unknownMember("\(receiver.typeName).\(name)\(called ? "()" : "")")
    }
}
