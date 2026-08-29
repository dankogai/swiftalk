extension Swiftalk {
    /// Milestone 0: `eval()` — source string in, value out (Design.md
    /// §13). One-shot: bindings do not survive the call. For a persistent
    /// environment (the REPL's engine), use `Swiftalk.Interpreter`.
    public static func eval(_ source: String) throws -> Value {
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
            do {
                for statement in program {
                    last = try execute(statement, in: environment, relaxed: relaxed)
                }
            } catch is ControlFlow {
                throw SwiftalkError.syntax("'break'/'continue' outside a loop")
            }
            return last
        }
    }

    /// True when `source` is a syntactically incomplete *prefix* — open
    /// brackets awaiting their close — so a REPL should read more lines
    /// rather than report an error. Anything else (complete or genuinely
    /// malformed) returns false.
    public static func needsMoreInput(_ source: String) -> Bool {
        var lexer = Lexer(source)
        guard let tokens = try? lexer.tokenize() else { return false }
        var depth = 0
        for token in tokens {
            switch token {
            case .punct("["), .punct("("), .punct("{"): depth += 1
            case .punct("]"), .punct(")"), .punct("}"): depth -= 1
            default: break
            }
        }
        return depth > 0
    }
}

typealias Interpreter = Swiftalk.Interpreter

/// A binding: its mutability, its type lock (Design.md §3), and its value.
/// The lock is fixed at declaration — from the annotation if written,
/// inferred from the initializer otherwise — and every later assignment
/// must satisfy it.
struct Binding {
    let mutable: Bool
    let lock: TypeAnnotation
    var value: Value
}

/// A lexical scope. Function calls make a child of the function's
/// captured environment; lookups and assignments walk the parent chain.
final class Environment {
    private var bindings: [String: Binding] = [:]
    private let parent: Environment?

    init(parent: Environment? = nil) {
        self.parent = parent
    }

    func declare(_ name: String, _ binding: Binding) throws {
        guard bindings[name] == nil else {
            throw SwiftalkError.type("redeclaration of '\(name)'")
        }
        bindings[name] = binding
    }

    func assign(_ name: String, _ value: Value) throws {
        guard var binding = bindings[name] else {
            if let parent {
                try parent.assign(name, value)
                return
            }
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
        bindings[name] != nil || (parent?.has(name) ?? false)
    }

    func lookup(_ name: String) throws -> Value {
        if let binding = bindings[name] { return binding.value }
        if let parent { return try parent.lookup(name) }
        throw SwiftalkError.type("undefined variable '\(name)'")
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
    ["Nil", "Bool", "Int", "Double", "String", "Array", "Dictionary", "Function"]

/// The hidden binding through which `$(...)` finds the current function
/// (§2.4). `@` cannot appear in a swiftalk identifier, so user code can
/// never collide with it.
private let calleeKey = "@callee"

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
    case .assignment(let target, let expr):
        let value = try evaluate(expr, in: env)
        if case .variable(let name) = target, relaxed, !env.has(name) {
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
        try assign(target, value, in: env)
        return value
    case .expression(let expr):
        return try evaluate(expr, in: env)
    case .ifS(let condition, let then, let elseBranch):
        guard case .bool(let flag) = try evaluate(condition, in: env) else {
            throw SwiftalkError.type("the 'if' condition must be a Bool — nothing is truthy (§3b)")
        }
        if flag {
            try runBlock(then, in: env)
        } else if let elseBranch {
            try runBlock(elseBranch, in: env)
        }
        return .nil
    case .whileS(let condition, let body):
        while true {
            guard case .bool(let flag) = try evaluate(condition, in: env) else {
                throw SwiftalkError.type("the 'while' condition must be a Bool — nothing is truthy (§3b)")
            }
            guard flag, try runLoopBody(body, in: env) else { break }
        }
        return .nil
    case .repeatS(let body, let condition):
        while true {
            guard try runLoopBody(body, in: env) else { break }
            guard case .bool(let flag) = try evaluate(condition, in: env) else {
                throw SwiftalkError.type("the 'repeat' condition must be a Bool — nothing is truthy (§3b)")
            }
            guard flag else { break }
        }
        return .nil
    case .forS(let name, let sequence, let body):
        for element in try elements(of: try evaluate(sequence, in: env)) {
            let scope = Environment(parent: env)
            if name != "_" {
                try scope.declare(name, Binding(
                    mutable: false,
                    lock: TypeAnnotation(name: element.typeName, optional: true),
                    value: element))
            }
            guard try runLoopBody(body, in: scope, freshScope: false) else { break }
        }
        return .nil
    case .breakS:
        throw ControlFlow.break
    case .continueS:
        throw ControlFlow.continue
    }
}

/// `break`/`continue` travel as thrown signals; loops catch them, and
/// `apply` refuses to let them escape a function body.
enum ControlFlow: Swift.Error {
    case `break`
    case `continue`
}

/// Runs a block in a fresh child scope (block-local let/var, §2.2-style
/// lexical scoping).
private func runBlock(_ body: [Stmt], in env: Environment) throws {
    let scope = Environment(parent: env)
    for statement in body {
        _ = try execute(statement, in: scope)
    }
}

/// Runs one loop iteration; returns false when the loop should stop
/// (`break`), true to keep going (`continue` just ends the iteration).
private func runLoopBody(_ body: [Stmt], in env: Environment, freshScope: Bool = true) throws -> Bool {
    let scope = freshScope ? Environment(parent: env) : env
    do {
        for statement in body {
            _ = try execute(statement, in: scope)
        }
    } catch ControlFlow.break {
        return false
    } catch ControlFlow.continue {
        return true
    }
    return true
}

/// What `for`-`in` iterates (§10's Sequence conformers): Array elements;
/// String graphemes (as single-Character Strings until a Character type
/// lands); Dictionary [key, value] pairs (until tuples land).
private func elements(of sequence: Value) throws -> [Value] {
    switch sequence {
    case .array(let a):
        return a
    case .string(let s):
        return s.map { .string(String($0)) }
    case .dictionary(let d):
        return d.map { .array([$0.key, $0.value]) }
    default:
        throw SwiftalkError.type("cannot iterate a \(sequence.typeName)")
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
    case .comparison(let op, let lhs, let rhs):
        return try compare(op, try evaluate(lhs, in: env), try evaluate(rhs, in: env))
    case .ternary(let condition, let thenBranch, let elseBranch):
        guard case .bool(let flag) = try evaluate(condition, in: env) else {
            throw SwiftalkError.type("the '?:' condition must be a Bool — nothing is truthy (§3b)")
        }
        return try evaluate(flag ? thenBranch : elseBranch, in: env)
    case .function(let parameters, let body):
        return .function(FunctionObject(parameters: parameters, body: body, closure: env))
    case .call(let callee, let args):
        guard case .function(let fn) = try evaluate(callee, in: env) else {
            let v = try evaluate(callee, in: env)
            throw SwiftalkError.type("cannot call a \(v.typeName)")
        }
        return try apply(fn, args: try evaluateArgs(args, in: env))
    case .selfCall(let args):
        guard case .function(let fn) = try? env.lookup(calleeKey) else {
            throw SwiftalkError.type("'$()' recurses — it only works inside a function")
        }
        return try apply(fn, args: try evaluateArgs(args, in: env))
    case .method(let receiver, let name, let args, let called):
        return try method(on: try evaluate(receiver, in: env), name: name,
                          args: try args.map { try evaluate($0, in: env) }, called: called)
    case .subscript(let base, let index):
        return try subscriptRead(try evaluate(base, in: env), try evaluate(index, in: env))
    case .range(let op, let lhs, let rhs):
        // Provisional: ranges are eager [Int] arrays (a lazy Range type
        // is an open design question). Like Swift, a > b traps.
        guard case .int(let a) = try evaluate(lhs, in: env),
              case .int(let b) = try evaluate(rhs, in: env) else {
            throw SwiftalkError.type("range bounds must be Ints")
        }
        guard a <= b else {
            throw SwiftalkError.type("range lower bound \(a) exceeds upper bound \(b)")
        }
        return op == "..."
            ? .array((a...b).map { .int($0) })
            : .array((a..<b).map { .int($0) })   // a ..< a is empty, as in Swift
    case .interpolation(let parts):
        // Swift-style display: a String embeds raw; everything else embeds
        // as its .String() source form (round 23; decided for
        // interpolation, `print` proper still OPEN).
        var out = ""
        for part in parts {
            switch try evaluate(part, in: env) {
            case .string(let s): out += s
            case let v:          out += v.sourceString()
            }
        }
        return .string(out)
    }
}

// MARK: subscripts

/// `a[i]` traps on a bad index like Swift; `d[k]` is the flat optional
/// lookup of §3a — nil for a missing key, indistinguishable from a
/// stored nil.
private func subscriptRead(_ container: Value, _ index: Value) throws -> Value {
    switch container {
    case .array(let a):
        guard case .int(let i) = index else {
            throw SwiftalkError.type("Array index must be an Int, not \(index.typeName)")
        }
        guard a.indices.contains(Int(i)) else {
            throw SwiftalkError.type("index \(i) out of range (count \(a.count))")
        }
        return a[Int(i)]
    case .dictionary(let d):
        return d[index] ?? .nil
    case .string:
        throw SwiftalkError.type("String subscripts are undecided (Design.md §11)")
    default:
        throw SwiftalkError.type("cannot subscript \(container.typeName)")
    }
}

/// A subscripted store: replaces an array element (bad index traps, as
/// on read), or sets a dictionary key — where `d[k] = nil` deletes the
/// key, Swift-compatible (round 15, flagged).
private func subscriptWrite(_ container: Value, _ index: Value, _ newValue: Value) throws -> Value {
    switch container {
    case .array(var a):
        guard case .int(let i) = index else {
            throw SwiftalkError.type("Array index must be an Int, not \(index.typeName)")
        }
        guard a.indices.contains(Int(i)) else {
            throw SwiftalkError.type("index \(i) out of range (count \(a.count))")
        }
        a[Int(i)] = newValue
        return .array(a)
    case .dictionary(var d):
        d[index] = newValue == .nil ? nil : newValue
        return .dictionary(d)
    case .string:
        throw SwiftalkError.type("String subscripts are undecided (Design.md §11)")
    default:
        throw SwiftalkError.type("cannot subscript \(container.typeName)")
    }
}

/// Assigns through an lvalue path. Subscript paths are read-modify-write
/// on COW values: indices evaluate once, left to right; the rebuilt
/// container lands back in the root binding, whose mutability and type
/// lock still govern.
private func assign(_ target: LValue, _ value: Value, in env: Environment) throws {
    var indexExprs: [Expr] = []
    var root = target
    while case .index(let base, let index) = root {
        indexExprs.insert(index, at: 0)
        root = base
    }
    guard case .variable(let name) = root else { fatalError("unreachable") }
    if indexExprs.isEmpty {
        try env.assign(name, value)
        return
    }
    let indices = try indexExprs.map { try evaluate($0, in: env) }
    func rebuild(_ container: Value, _ depth: Int) throws -> Value {
        if depth == indices.count - 1 {
            return try subscriptWrite(container, indices[depth], value)
        }
        let inner = try subscriptRead(container, indices[depth])
        return try subscriptWrite(container, indices[depth],
                                  try rebuild(inner, depth + 1))
    }
    try env.assign(name, try rebuild(try env.lookup(name), 0))
}

private func evaluateArgs(
    _ args: [(label: String?, expr: Expr)], in env: Environment
) throws -> [(label: String?, value: Value)] {
    try args.map { ($0.label, try evaluate($0.expr, in: env)) }
}

/// Applies a function (§2.4): declared parameters get strict arity with
/// optional, reorderable labels (§2.3, round 10); no declared parameters
/// means variadic (round 14). `$` is the argument array, `$N` its
/// elements, and `@callee` lets `$()` recurse.
func apply(_ fn: FunctionObject, args: [(label: String?, value: Value)]) throws -> Value {
    var ordered: [Value]
    if fn.parameters.isEmpty {
        if let label = args.compactMap(\.label).first {
            throw SwiftalkError.type(
                "unknown argument label '\(label)': this function declares no parameter names")
        }
        ordered = args.map(\.value)
    } else {
        guard args.count == fn.parameters.count else {
            throw SwiftalkError.type(
                "expected \(fn.parameters.count) argument(s), got \(args.count)")
        }
        var slots = [Value?](repeating: nil, count: fn.parameters.count)
        for (label, value) in args where label != nil {
            guard let index = fn.parameters.firstIndex(of: label!) else {
                throw SwiftalkError.type("unknown argument label '\(label!)'")
            }
            guard slots[index] == nil else {
                throw SwiftalkError.type("duplicate argument label '\(label!)'")
            }
            slots[index] = value
        }
        var positionals = args.filter { $0.label == nil }.map(\.value)[...]
        ordered = try slots.map { slot in
            if let slot { return slot }
            guard let next = positionals.popFirst() else {
                throw SwiftalkError.type("missing argument")
            }
            return next
        }
    }

    let local = Environment(parent: fn.closure)
    for (name, value) in zip(fn.parameters, ordered) {
        try local.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: value.typeName, optional: true),
            value: value))
    }
    // `$` — per-closure, shadowing any outer one (§2.4). `$N` needs no
    // bindings of its own: the parser desugars it to `$[N]`, literally.
    try local.declare("$", Binding(
        mutable: false,
        lock: TypeAnnotation(name: "Array", optional: false),
        value: .array(ordered)))
    try local.declare(calleeKey, Binding(
        mutable: false,
        lock: TypeAnnotation(name: "Function", optional: false),
        value: .function(fn)))

    var last = Value.nil
    do {
        for statement in fn.body {
            last = try execute(statement, in: local)
        }
    } catch is ControlFlow {
        throw SwiftalkError.syntax("'break'/'continue' outside a loop")
    }
    return last
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

/// `==`/`!=` on any same-type pair (Equatable, §10); `< <= > >=` on
/// Int/Double/String (Comparable). `x == nil` is a valid question of
/// anything (§3a); mixing other types is a type error, not `false`.
private func compare(_ op: String, _ lhs: Value, _ rhs: Value) throws -> Value {
    switch op {
    case "==", "!=":
        if case .nil = lhs {} else if case .nil = rhs {} else {
            guard lhs.typeName == rhs.typeName else {
                throw SwiftalkError.type(
                    "'\(op)' is not defined between \(lhs.typeName) and \(rhs.typeName)")
            }
        }
        return .bool(op == "==" ? lhs == rhs : lhs != rhs)
    default:
        let ascending: Bool
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)):       ascending = a < b
        case (.double(let a), .double(let b)): ascending = a < b
        case (.string(let a), .string(let b)): ascending = a < b
        default:
            throw SwiftalkError.type(
                "'\(op)' is not defined between \(lhs.typeName) and \(rhs.typeName)")
        }
        let equal = lhs == rhs
        switch op {
        case "<":  return .bool(ascending)
        case "<=": return .bool(ascending || equal)
        case ">":  return .bool(!ascending && !equal)
        case ">=": return .bool(!ascending)
        default:   fatalError("unreachable operator \(op)")
        }
    }
}

/// Members so far: `.String()` (the round-trip law, §3d), `.type` (§3,
/// as a name for now), and `.count` on the Sequence conformers (§10).
private func method(on receiver: Value, name: String, args: [Value], called: Bool) throws -> Value {
    switch (name, called) {
    case ("String", true):
        guard args.isEmpty else {
            throw SwiftalkError.type(".String() format arguments are a later milestone")
        }
        return .string(receiver.sourceString())
    case ("type", false):
        // Types will become constructor Functions (§10); until Function
        // lands as a constructor, .type evaluates to the type's name.
        return .string(receiver.typeName)
    case ("count", false):
        switch receiver {
        case .array(let a):      return .int(Int64(a.count))
        case .string(let s):     return .int(Int64(s.count))   // graphemes (§11)
        case .dictionary(let d): return .int(Int64(d.count))
        default:
            throw SwiftalkError.unknownMember("\(receiver.typeName).count")
        }
    default:
        throw SwiftalkError.unknownMember("\(receiver.typeName).\(name)\(called ? "()" : "")")
    }
}
