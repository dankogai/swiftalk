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
        private let outputBox = OutputBox()

        /// Where `print`/`debugPrint` write. Defaults to stdout; an
        /// embedder may redirect it (the Lua way — the host owns I/O).
        public var output: (String) -> Void {
            get { outputBox.write }
            set { outputBox.write = newValue }
        }

        /// `relaxed` is REPL mode (Design.md §2.2): assignment to an
        /// undeclared name implicitly declares a `var` — still type-locked
        /// from then on. File mode (the default) rejects it.
        public init(relaxed: Bool = false) {
            self.relaxed = relaxed
            installBuiltins()
        }

        /// The stdlib arrives as ordinary let-bound Function values in
        /// the global environment (§2.4) — not keywords.
        private func installBuiltins() {
            let box = outputBox
            declareBuiltin("print") { args in
                // Raw display: Strings bare, everything else source form
                // (round 35, completing round 23's display question).
                box.write(args.map(displayString).joined(separator: " ") + "\n")
                return .nil
            }
            declareBuiltin("debugPrint") { args in
                // .debugDescription for everything: quoted strings, hex
                // numbers (round 37) — for the programmer's sake.
                box.write(args.map { $0.sourceString(debug: true) }.joined(separator: " ") + "\n")
                return .nil
            }
            // Types and protocols are values too (round 39): the global
            // names Int, String, ..., Sequence, ... bind the singleton
            // objects that `.type` returns — identity comparison works.
            for (name, object) in Builtins.types.merging(Builtins.protocols, uniquingKeysWith: { a, _ in a }) {
                try! environment.declare(name, Binding(
                    mutable: false,
                    lock: TypeAnnotation(name: "Function", optional: false),
                    value: .function(object)))
            }
        }

        private func declareBuiltin(_ name: String, _ body: @escaping ([Value]) throws -> Value) {
            let fn = FunctionObject(parameters: [], body: [], closure: environment, builtin: body)
            try! environment.declare(name, Binding(
                mutable: false,
                lock: TypeAnnotation(name: "Function", optional: false),
                value: .function(fn)))
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
            } catch is ReturnSignal {
                throw SwiftalkError.syntax("'return' outside a function")
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

/// Reference box for the output sink, so builtins capture the box —
/// not the Interpreter — and no retain cycle forms.
final class OutputBox {
    var write: (String) -> Void = { Swift.print($0, terminator: "") }
}

/// The raw display form (round 35): a String shows itself bare; every
/// other value shows its .String() source form. Shared by `print` and
/// string interpolation.
func displayString(_ value: Value) -> String {
    if case .string(let s) = value { return s }
    return value.sourceString()
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
        if !binding.mutable {
            // A let holding .todo accepts exactly one assignment — its
            // deferred initialization (round 44). Once real, it is frozen.
            guard case .function(let f) = binding.value, case .todo = f.role else {
                throw SwiftalkError.type("cannot assign to let constant '\(name)'")
            }
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
    ["Nil", "Bool", "Int", "Double", "String", "Array", "Dictionary", "Function", "Range", "Sequence"]

/// The hidden binding through which `$(...)` finds the current function
/// (§2.4). `@` cannot appear in a swiftalk identifier, so user code can
/// never collide with it.
private let calleeKey = "@callee"

/// The hot dispatcher: recursion (function bodies, loops) runs through
/// here, so its frame must stay tiny — Swift allocates one frame for
/// the union of a switch's cases, and the evaluator's Swift-stack
/// depth is the language's recursion budget (see round 45's war
/// story). Everything with real locals lives in `executeSlow`.
func execute(_ statement: Stmt, in env: Environment, relaxed: Bool = false) throws -> Value {
    switch statement {
    case .expression(let expr):
        return try evaluate(expr, in: env)
    case .returnS(let expr):
        throw ReturnSignal(value: try expr.map { try evaluate($0, in: env) } ?? .nil)
    case .breakS:
        throw ControlFlow.break
    case .continueS:
        throw ControlFlow.continue
    default:
        return try executeSlow(statement, in: env, relaxed: relaxed)
    }
}

private func executeSlow(_ statement: Stmt, in env: Environment, relaxed: Bool) throws -> Value {
    switch statement {
    case .declaration(let mutable, let name, let annotation, let initializer):
        // An annotation naming a user enum enables `.case` initializers
        // (round 45), the way `Function` enables `.todo` (round 44).
        let annotatedEnum = try annotation.flatMap { try resolveEnumAnnotation($0, in: env) }
        let value: Value
        if case .memberLiteral("todo") = initializer,
           annotation == nil || annotation?.name == "Function" {
            // `let f: Function = .todo` (round 44): a placeholder that
            // grants an immutable binding exactly one later assignment.
            value = .function(Builtins.todo)
        } else if let et = annotatedEnum, case .memberLiteral(let caseName) = initializer {
            value = try constructEnumCase(et, caseName, args: [], called: false)
        } else if let et = annotatedEnum,
                  case .call(.memberLiteral(let caseName), let argExprs) = initializer {
            value = try constructEnumCase(
                et, caseName,
                args: try argExprs.map { ($0.label, try evaluate($0.expr, in: env)) },
                called: true)
        } else {
            value = try evaluate(initializer, in: env)
        }
        let lock: TypeAnnotation
        if let annotation {
            guard knownTypeNames.contains(annotation.name) || annotatedEnum != nil
                    || isUserType(annotation.name, in: env) else {
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
        let it = try iterator(of: try evaluate(sequence, in: env))
        while let element = try it.next() {
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
    case .returnS(let expr):
        throw ReturnSignal(value: try expr.map { try evaluate($0, in: env) } ?? .nil)
    case .enumDecl(let name, let caseOrder, let cases):
        let et = EnumType(name: name, caseOrder: caseOrder, cases: cases)
        let constructor = FunctionObject(
            parameters: [], body: [], closure: env,
            builtin: { _ in
                throw SwiftalkError.type(
                    "construct \(name) via a case: \(name).\(caseOrder.first ?? "someCase")")
            },
            role: .enumType(et))
        et.constructor = constructor
        try env.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: "Function", optional: false),
            value: .function(constructor)))
        return .function(constructor)
    case .structDecl(let name, let propertyOrder, let properties):
        let st = StructType(name: name, propertyOrder: propertyOrder,
                            properties: properties, declEnv: env)
        let constructor = FunctionObject(
            parameters: [], body: [], closure: env, builtin: nil,
            role: .structType(st))
        st.constructor = constructor
        try env.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: "Function", optional: false),
            value: .function(constructor)))
        return .function(constructor)
    case .switchS(let subjectExpr, let clauses, let defaultBody):
        let subject = try evaluate(subjectExpr, in: env)
        for clause in clauses {
            for pattern in clause.patterns {
                if let bindings = try match(pattern, subject, in: env) {
                    try runBlock(clause.body, in: env, bindings: bindings)
                    return .nil
                }
            }
        }
        if let defaultBody {
            try runBlock(defaultBody, in: env)
            return .nil
        }
        // Runtime exhaustiveness (§7): reaching a value no case matches,
        // with no default, is an error — never a silent skip.
        throw SwiftalkError.type(
            "switch is not exhaustive — nothing matches \(subject.sourceString())")
    case .ifCaseS(let pattern, let subjectExpr, let then, let elseBranch):
        let subject = try evaluate(subjectExpr, in: env)
        if let bindings = try match(pattern, subject, in: env) {
            try runBlock(then, in: env, bindings: bindings)
        } else if let elseBranch {
            try runBlock(elseBranch, in: env)
        }
        return .nil
    }
}

/// Matches a pattern against a value: nil for no match, else the
/// bindings a `case let` destructuring produced.
private func match(_ pattern: Pattern, _ subject: Value,
                   in env: Environment) throws -> [(String, Value)]? {
    switch pattern {
    case .wildcard:
        return []
    case .expr(let e):
        let v = try evaluate(e, in: env)
        if v == subject { return [] }
        // A Range pattern matches an Int by containment (Swift's ~=).
        if case .range(let lower, let upper, let closed) = v, case .int(let i) = subject {
            if lower <= i && (closed ? i <= upper : i < upper) { return [] }
        }
        return nil
    case .enumCase(let name, let bindings):
        guard case .enumCase(let ev) = subject, ev.caseName == name else { return nil }
        guard let bindings else { return [] }         // bare .name matches any payload
        guard bindings.count == ev.associated.count else {
            throw SwiftalkError.type(
                "pattern .\(name) destructures \(bindings.count) value(s); the case has \(ev.associated.count)")
        }
        var bound: [(String, Value)] = []
        for (binding, value) in zip(bindings, ev.associated) {
            if case .bind(let bindingName) = binding {
                bound.append((bindingName, value))
            }
        }
        return bound
    }
}

/// Resolves an annotation to a user enum type when it names one; nil
/// for built-ins and unknowns (the caller validates those).
private func resolveEnumAnnotation(_ annotation: TypeAnnotation,
                                   in env: Environment) throws -> EnumType? {
    guard !knownTypeNames.contains(annotation.name),
          let value = try? env.lookup(annotation.name),
          case .function(let f) = value,
          case .enumType(let et) = f.role else { return nil }
    return et
}

/// True when `name` binds a user-declared type (enum or struct) in
/// scope — annotations may name them like any built-in.
private func isUserType(_ name: String, in env: Environment) -> Bool {
    guard let value = try? env.lookup(name), case .function(let f) = value else {
        return false
    }
    switch f.role {
    case .enumType, .structType: return true
    default: return false
    }
}

/// Constructs `Enum.case(...)` (round 45): labels optional and
/// reorderable per §2.3; declared associated types checked at runtime
/// per §3.
func constructEnumCase(_ et: EnumType, _ caseName: String,
                       args: [(label: String?, value: Value)], called: Bool) throws -> Value {
    guard let params = et.cases[caseName] else {
        throw SwiftalkError.unknownMember("\(et.name).\(caseName)")
    }
    guard called || args.isEmpty else { fatalError("unreachable") }
    if !called || params.isEmpty {
        guard params.isEmpty else {
            throw SwiftalkError.type(
                "\(et.name).\(caseName) has associated values — call it")
        }
        guard args.isEmpty else {
            throw SwiftalkError.type("\(et.name).\(caseName) takes no associated values")
        }
        return .enumCase(EnumCaseValue(type: et, caseName: caseName, associated: []))
    }
    guard args.count == params.count else {
        throw SwiftalkError.type(
            "\(et.name).\(caseName) takes \(params.count) associated value(s), got \(args.count)")
    }
    var slots = [Value?](repeating: nil, count: params.count)
    for (label, value) in args where label != nil {
        guard let index = params.firstIndex(where: { $0.label == label }) else {
            throw SwiftalkError.type("unknown label '\(label!)' for \(et.name).\(caseName)")
        }
        guard slots[index] == nil else {
            throw SwiftalkError.type("duplicate label '\(label!)'")
        }
        slots[index] = value
    }
    var positionals = args.filter { $0.label == nil }.map(\.value)[...]
    let associated: [Value] = try slots.enumerated().map { index, slot in
        let value: Value
        if let slot { value = slot }
        else if let next = positionals.popFirst() { value = next }
        else { throw SwiftalkError.type("missing associated value") }
        if let expected = params[index].typeName, value.typeName != expected {
            throw SwiftalkError.type(
                "\(et.name).\(caseName) expects \(expected), got \(value.typeName)")
        }
        return value
    }
    return .enumCase(EnumCaseValue(type: et, caseName: caseName, associated: associated))
}

/// `break`/`continue` travel as thrown signals; loops catch them, and
/// `apply` refuses to let them escape a function body.
enum ControlFlow: Swift.Error {
    case `break`
    case `continue`
}

/// `return` (round 41) travels the same way; `apply` catches it at the
/// function boundary.
struct ReturnSignal: Swift.Error {
    let value: Value
}

/// Runs a block in a fresh child scope (block-local let/var, §2.2-style
/// lexical scoping); `bindings` are pattern-match spoils (`case let`).
private func runBlock(_ body: [Stmt], in env: Environment,
                      bindings: [(String, Value)] = []) throws {
    let scope = Environment(parent: env)
    for (name, value) in bindings {
        try scope.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: value.typeName, optional: true),
            value: value))
    }
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

/// What `for`-`in` (and map/filter/reduce) iterate — the Sequence
/// conformers of §10: Array elements; String graphemes (as
/// single-Character Strings until a Character type lands); Dictionary
/// [key, value] pairs (until tuples land); Range lazily, element by
/// element — a huge Range never materializes.
/// A pull-based iterator whose `next` may throw — lazy Sequence pulls
/// run swiftalk code (round 41), and swiftalk code errors.
final class ValueIterator {
    private let nextImpl: () throws -> Value?
    init(_ next: @escaping () throws -> Value?) {
        self.nextImpl = next
    }
    func next() throws -> Value? {
        try nextImpl()
    }
}

func iterator(of sequence: Value) throws -> ValueIterator {
    switch sequence {
    case .array(let a):
        var it = a.makeIterator()
        return ValueIterator { it.next() }
    case .string(let s):
        var it = s.makeIterator()
        return ValueIterator { it.next().map { .string(String($0)) } }
    case .dictionary(let d):
        var it = d.makeIterator()
        return ValueIterator { it.next().map { .array([$0.key, $0.value]) } }
    case .range(let lower, let upper, let closed):
        var current = lower
        var exhausted = false
        return ValueIterator {
            if exhausted { return nil }
            if closed {
                let v = current
                if current == upper { exhausted = true } else { current += 1 }
                return .int(v)
            }
            guard current < upper else {
                exhausted = true
                return nil
            }
            let v = current
            current += 1
            return .int(v)
        }
    case .sequence(let s):
        return s.makeIterator()
    default:
        throw SwiftalkError.type("cannot iterate a \(sequence.typeName)")
    }
}

/// Materializes any Sequence conformer eagerly (the caller's rope for
/// infinite ones).
func collect(_ sequence: Value) throws -> [Value] {
    var out: [Value] = []
    let it = try iterator(of: sequence)
    while let element = try it.next() {
        out.append(element)
    }
    return out
}

extension SequenceObject {
    /// A fresh pull-iteration. Generators restart from their initial
    /// state each time — a Sequence value is re-iterable, like any value.
    func makeIterator() -> ValueIterator {
        switch kind {
        case .generator(let initial, let next):
            var state = initial
            var done = false
            return ValueIterator {
                if done { return nil }
                let (element, local) = try run(next, ordered: state)
                if element == .nil {
                    done = true      // returning nil ends the sequence
                    return nil
                }
                guard case .array(let newState) = try local.lookup("$") else {
                    throw SwiftalkError.type("a Sequence generator's '$' must stay an Array")
                }
                state = newState
                return element
            }
        case .mapped(let base, let fn):
            let it = base.makeIterator()
            return ValueIterator {
                try it.next().map { try apply(fn, args: [(nil, $0)]) }
            }
        case .filtered(let base, let fn):
            let it = base.makeIterator()
            return ValueIterator {
                while let element = try it.next() {
                    guard case .bool(let keep) = try apply(fn, args: [(nil, element)]) else {
                        throw SwiftalkError.type("the .filter Function must return a Bool")
                    }
                    if keep { return element }
                }
                return nil
            }
        }
    }
}

/// A Range's element count, without materializing (overflow-checked:
/// the full Int64 span has no representable count).
private func rangeCount(from lower: Int64, to upper: Int64, closed: Bool) throws -> Int64 {
    let (span, overflow) = upper.subtractingReportingOverflow(lower)
    guard !overflow, !(closed && span == Int64.max) else {
        throw SwiftalkError.overflow("this Range's count does not fit in an Int")
    }
    return closed ? span + 1 : span
}

/// The hot dispatcher (see `execute`): arithmetic, comparisons,
/// ternary, and calls — the recursion diet — stay in this tiny frame;
/// everything else defers to `evaluateSlow`.
func evaluate(_ expr: Expr, in env: Environment) throws -> Value {
    switch expr {
    case .literal(let v):
        return v
    case .variable(let name):
        return try env.lookup(name)
    case .binary(let op, let lhs, let rhs):
        return try binary(op, try evaluate(lhs, in: env), try evaluate(rhs, in: env))
    case .comparison(let op, let lhs, let rhs):
        return try compare(op, try evaluate(lhs, in: env), try evaluate(rhs, in: env))
    case .ternary(let condition, let thenBranch, let elseBranch):
        guard case .bool(let flag) = try evaluate(condition, in: env) else {
            throw SwiftalkError.type("the '?:' condition must be a Bool — nothing is truthy (§3b)")
        }
        return try evaluate(flag ? thenBranch : elseBranch, in: env)
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
    case .subscript(let base, let index):
        return try subscriptRead(try evaluate(base, in: env), try evaluate(index, in: env))
    default:
        return try evaluateSlow(expr, in: env)
    }
}

private func evaluateSlow(_ expr: Expr, in env: Environment) throws -> Value {
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
    case .method(let receiverExpr, "remove", let argExprs, true):
        // d.remove(k) mutates (round 37): the receiver must be an
        // assignable var path; the removed value (or nil) comes back.
        guard argExprs.count == 1, argExprs[0].label == nil else {
            throw SwiftalkError.type(".remove(key) takes exactly one unlabeled argument")
        }
        guard case .dictionary(var d) = try evaluate(receiverExpr, in: env) else {
            throw SwiftalkError.unknownMember(
                "\(try evaluate(receiverExpr, in: env).typeName).remove()")
        }
        guard let target = asLValue(receiverExpr) else {
            throw SwiftalkError.type("cannot mutate an immutable Dictionary — bind it to a var first")
        }
        let removed = d.removeValue(forKey: try evaluate(argExprs[0].expr, in: env)) ?? .nil
        try assign(target, .dictionary(d), in: env)
        return removed
    case .method(let receiver, let name, let args, let called):
        return try method(on: try evaluate(receiver, in: env), name: name,
                          args: try args.map { ($0.label, try evaluate($0.expr, in: env)) },
                          called: called)
    case .subscript(let base, let index):
        return try subscriptRead(try evaluate(base, in: env), try evaluate(index, in: env))
    case .range(let op, let lhs, let rhs):
        // Range<I> (round 38): a lazy first-class value. Int bounds only
        // (BigInt someday, Double never). Like Swift, a > b traps.
        guard case .int(let a) = try evaluate(lhs, in: env),
              case .int(let b) = try evaluate(rhs, in: env) else {
            throw SwiftalkError.type("Range bounds must be Ints")
        }
        guard a <= b else {
            throw SwiftalkError.type("range lower bound \(a) exceeds upper bound \(b)")
        }
        return .range(from: a, to: b, closed: op == "...")
    case .memberLiteral(let name):
        // Format members (.quoted, .hex, ...) — provisionally String
        // values until enums land (round 42; §3d format vocabularies
        // are meant to be enums).
        return .string(name)
    case .interpolation(let parts):
        // Swift-style display: a String embeds raw; everything else embeds
        // as its .String() source form (round 23; decided for
        // interpolation, `print` proper still OPEN).
        var out = ""
        for part in parts {
            out += displayString(try evaluate(part, in: env))
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
    case .range(let lower, let upper, let closed):
        // Offset subscript: r[i] is the i-th element, bounds-checked.
        guard case .int(let i) = index else {
            throw SwiftalkError.type("Range index must be an Int, not \(index.typeName)")
        }
        let count = try rangeCount(from: lower, to: upper, closed: closed)
        guard (0..<count).contains(i) else {
            throw SwiftalkError.type("index \(i) out of range (count \(count))")
        }
        return .int(lower + i)
    case .string:
        throw SwiftalkError.type("String subscripts are undecided (Design.md §11)")
    default:
        throw SwiftalkError.type("cannot subscript \(container.typeName)")
    }
}

/// A subscripted store: replaces an array element (bad index traps, as
/// on read), or sets a dictionary key. `d[k] = nil` stores nil — a
/// deliberate divergence from Swift (round 35): nil is a right value
/// for a key, and presence is `d.has(k)`'s question, so a missing key
/// and a key holding nil stay semantically distinct.
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
        d[index] = newValue
        return .dictionary(d)
    case .string:
        throw SwiftalkError.type("String subscripts are undecided (Design.md §11)")
    default:
        throw SwiftalkError.type("cannot subscript \(container.typeName)")
    }
}

/// The evaluator's twin of the parser's lvalue converter, for mutating
/// methods: a variable or subscript/property chain rooted in one.
private func asLValue(_ expr: Expr) -> LValue? {
    switch expr {
    case .variable(let name):
        return .variable(name)
    case .subscript(let base, let index):
        guard let inner = asLValue(base) else { return nil }
        return .index(inner, index)
    case .method(let base, let name, let args, false) where args.isEmpty:
        guard let inner = asLValue(base) else { return nil }
        return .property(inner, name)
    default:
        return nil
    }
}

/// The memberwise initializer (round 46): labels optional and
/// reorderable per §2.3, positionals fill in declaration order,
/// missing properties take their defaults (evaluated in the struct's
/// declaring environment), annotations checked per §3.
func constructStruct(_ st: StructType,
                     args: [(label: String?, value: Value)]) throws -> Value {
    var slots: [String: Value] = [:]
    var positionals: [Value] = []
    for (label, value) in args {
        if let label {
            guard st.properties[label] != nil else {
                throw SwiftalkError.type("\(st.name) has no property '\(label)'")
            }
            guard slots[label] == nil else {
                throw SwiftalkError.type("duplicate property '\(label)'")
            }
            slots[label] = value
        } else {
            positionals.append(value)
        }
    }
    var remaining = positionals[...]
    var values: [String: Value] = [:]
    for prop in st.propertyOrder {
        let def = st.properties[prop]!
        let value: Value
        if let given = slots[prop] {
            value = given
        } else if !remaining.isEmpty {
            value = remaining.removeFirst()
        } else if let defaultExpr = def.defaultExpr {
            value = try evaluate(defaultExpr, in: Environment(parent: st.declEnv))
        } else {
            throw SwiftalkError.type("missing property '\(prop)' of \(st.name)")
        }
        if let annotation = def.annotation {
            try checkValue(value, against: annotation, context: "\(st.name).\(prop)")
        }
        values[prop] = value
    }
    guard remaining.isEmpty else {
        throw SwiftalkError.type("too many values for \(st.name)")
    }
    return .structValue(StructValue(type: st, values: values))
}

/// The §3 lock check, standalone (shared by bindings and properties).
func checkValue(_ value: Value, against lock: TypeAnnotation, context: String) throws {
    if case .nil = value {
        guard lock.optional || lock.name == "Nil" else {
            throw SwiftalkError.type(
                "cannot assign nil to \(context) of type \(lock.name) — declare it \(lock.name)?")
        }
        return
    }
    guard value.typeName == lock.name else {
        throw SwiftalkError.type(
            "cannot assign \(value.typeName) to \(context) of type \(lock.name)\(lock.optional ? "?" : "")")
    }
}

/// Reads a struct property (assignment paths; expression reads go
/// through `method()`).
private func propertyRead(_ container: Value, _ name: String) throws -> Value {
    guard case .structValue(let sv) = container else {
        throw SwiftalkError.type("cannot assign through a property of \(container.typeName)")
    }
    guard let value = sv.values[name] else {
        throw SwiftalkError.unknownMember("\(sv.type.name).\(name)")
    }
    return value
}

/// Writes a struct property: the property must exist and be a `var`;
/// annotated properties re-check per §3, unannotated ones lock to the
/// current value's type.
private func propertyWrite(_ container: Value, _ name: String, _ newValue: Value) throws -> Value {
    guard case .structValue(var sv) = container else {
        throw SwiftalkError.type("cannot assign through a property of \(container.typeName)")
    }
    guard let def = sv.type.properties[name], let current = sv.values[name] else {
        throw SwiftalkError.unknownMember("\(sv.type.name).\(name)")
    }
    guard def.mutable else {
        throw SwiftalkError.type("cannot assign to let property '\(sv.type.name).\(name)'")
    }
    if let annotation = def.annotation {
        try checkValue(newValue, against: annotation, context: "\(sv.type.name).\(name)")
    } else if current != .nil, newValue.typeName != current.typeName {
        throw SwiftalkError.type(
            "cannot assign \(newValue.typeName) to \(sv.type.name).\(name) of type \(current.typeName)")
    }
    sv.values[name] = newValue
    return .structValue(sv)
}

/// One step of an assignment path: a subscript or a property.
private enum PathStep {
    case index(Value)
    case property(String)
}

/// Assigns through an lvalue path. Subscript/property paths are
/// read-modify-write on COW values: steps evaluate once, left to
/// right; the rebuilt container lands back in the root binding, whose
/// mutability and type lock still govern.
private func assign(_ target: LValue, _ value: Value, in env: Environment) throws {
    var steps: [PathStep] = []
    var root = target
    flatten: while true {
        switch root {
        case .index(let base, let indexExpr):
            steps.insert(.index(try evaluate(indexExpr, in: env)), at: 0)
            root = base
        case .property(let base, let name):
            steps.insert(.property(name), at: 0)
            root = base
        case .variable:
            break flatten
        }
    }
    guard case .variable(let name) = root else { fatalError("unreachable") }
    if steps.isEmpty {
        try env.assign(name, value)
        return
    }
    func read(_ container: Value, _ step: PathStep) throws -> Value {
        switch step {
        case .index(let i):        return try subscriptRead(container, i)
        case .property(let p):     return try propertyRead(container, p)
        }
    }
    func write(_ container: Value, _ step: PathStep, _ v: Value) throws -> Value {
        switch step {
        case .index(let i):        return try subscriptWrite(container, i, v)
        case .property(let p):     return try propertyWrite(container, p, v)
        }
    }
    func rebuild(_ container: Value, _ depth: Int) throws -> Value {
        if depth == steps.count - 1 {
            return try write(container, steps[depth], value)
        }
        let inner = try read(container, steps[depth])
        return try write(container, steps[depth], try rebuild(inner, depth + 1))
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
    // Calling a struct type IS the memberwise initializer (round 46).
    if case .structType(let st) = fn.role {
        return try constructStruct(st, args: args)
    }
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

    if let builtin = fn.builtin {
        return try builtin(ordered)
    }
    return try run(fn, ordered: ordered).result
}

/// Runs a non-builtin function body and also hands back its local
/// environment — generators (round 41) read the closure's final `$`
/// from it as the next state.
func run(_ fn: FunctionObject, ordered: [Value]) throws -> (result: Value, local: Environment) {
    let local = Environment(parent: fn.closure)
    for (name, value) in zip(fn.parameters, ordered) {
        try local.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: value.typeName, optional: true),
            value: value))
    }
    // `$` — per-closure, shadowing any outer one (§2.4) — is a *var*
    // since round 41 (Array-locked): generators reassign it to advance
    // their state. `$N` are entry snapshots of the arguments; `$N` ==
    // `$[N]` holds until `$` is reassigned.
    try local.declare("$", Binding(
        mutable: true,
        lock: TypeAnnotation(name: "Array", optional: false),
        value: .array(ordered)))
    for (index, value) in ordered.enumerated() {
        try local.declare("$\(index)", Binding(
            mutable: false,
            lock: TypeAnnotation(name: value.typeName, optional: true),
            value: value))
    }
    try local.declare(calleeKey, Binding(
        mutable: false,
        lock: TypeAnnotation(name: "Function", optional: false),
        value: .function(fn)))

    var last = Value.nil
    do {
        for statement in fn.body {
            last = try execute(statement, in: local)
        }
    } catch let signal as ReturnSignal {
        return (signal.value, local)
    } catch is ControlFlow {
        throw SwiftalkError.syntax("'break'/'continue' outside a loop")
    }
    return (last, local)
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
/// Rejects labeled arguments where a member takes none, yielding the
/// bare values.
private func plainValues(_ args: [(label: String?, value: Value)], for member: String) throws -> [Value] {
    if let label = args.compactMap(\.label).first {
        throw SwiftalkError.type("\(member) takes no argument label '\(label)'")
    }
    return args.map(\.value)
}

private func method(on receiver: Value, name: String,
                    args labeledArgs: [(label: String?, value: Value)], called: Bool) throws -> Value {
    // `.conforms(to:)` is the one member with a label; everything else
    // takes bare values.
    if (name, called) == ("conforms", true) {
        guard case .function(let t) = receiver else {
            throw SwiftalkError.type("'.conforms(to:)' is a question asked of a type")
        }
        guard labeledArgs.count == 1, labeledArgs[0].label == nil || labeledArgs[0].label == "to" else {
            throw SwiftalkError.type(".conforms(to:) takes exactly one argument")
        }
        guard case .function(let p) = labeledArgs[0].value, case .protocol(let protoName) = p.role else {
            throw SwiftalkError.type("the argument to .conforms(to:) must be a protocol")
        }
        switch t.role {
        case .type(let n), .protocol(let n):
            return .bool(Builtins.conformance[protoName]?.contains(n) ?? false)
        case .enumType, .structType:
            // User types get synthesized Equatable/Hashable (§10).
            return .bool(protoName == "Equatable" || protoName == "Hashable")
        case .plain, .todo:
            throw SwiftalkError.type("'.conforms(to:)' is a question asked of a type")
        }
    }
    // Member access on a user enum type constructs its cases (round 45):
    // Shape.circle(r: 3.0), Shape.point.
    if case .function(let f) = receiver, case .enumType(let et) = f.role,
       et.cases[name] != nil {
        return try constructEnumCase(et, name, args: labeledArgs, called: called)
    }
    // Case accessors (round 46) — the endless `if case .name(let v)`
    // ceremony, dissolved: value.casename extracts the associated
    // value(s) when the value IS that case, nil otherwise. One payload
    // comes bare, several come as an Array, none returns the case
    // value itself (so `s.point != nil` asks "is it .point?").
    if case .enumCase(let ev) = receiver, !called, ev.type.cases[name] != nil {
        guard ev.caseName == name else { return .nil }
        switch ev.associated.count {
        case 0:  return receiver
        case 1:  return ev.associated[0]
        default: return .array(ev.associated)
        }
    }
    // Struct property reads (round 46): p.x.
    if case .structValue(let sv) = receiver, !called, let value = sv.values[name] {
        return value
    }
    // .String(radix: n) — bare digits in any radix (round 20).
    if (name, called) == ("String", true),
       labeledArgs.count == 1, labeledArgs[0].label == "radix" {
        guard case .int(let radix) = labeledArgs[0].value, (2...36).contains(radix) else {
            throw SwiftalkError.type(".String(radix:) takes an Int in 2...36")
        }
        guard case .int(let i) = receiver else {
            throw SwiftalkError.type(".String(radix:) is an Int's format")
        }
        return .string(String(i, radix: Int(radix)))
    }
    let args = try plainValues(labeledArgs, for: ".\(name)")
    switch (name, called) {
    case ("String", true):
        guard args.count <= 1 else {
            throw SwiftalkError.type(".String() takes at most one format argument")
        }
        switch args.first {
        case nil:
            // Argless .String() is description (round 42): a String is
            // itself — quoting is explicit via .String(.quoted).
            return .string(displayString(receiver))
        case .string("quoted")?:
            return .string(receiver.sourceString())
        case .string("hex")?:
            // Literal-ready, prefixed — round-trips (rounds 20–21).
            switch receiver {
            case .int:            return .string(receiver.sourceString(debug: true))
            case .double(let d):  return .string(Value.hexFloat(d))
            default:
                throw SwiftalkError.type(".String(.hex) is a number's format")
            }
        case .string("oct")?, .string("bin")?:
            guard case .int(let i) = receiver else {
                throw SwiftalkError.type(".String(.oct)/.String(.bin) are an Int's formats")
            }
            let (prefix, radix) = args.first == .string("oct") ? ("0o", 8) : ("0b", 2)
            return .string((i < 0 ? "-" : "") + prefix + String(i.magnitude, radix: radix))
        case let other?:
            throw SwiftalkError.type("unknown .String() format \(other.sourceString())")
        }
    case ("Type", false):
        // x.Type (round 40; né x.type) — the constructor Function, à la
        // JS's .constructor: the singleton the global name binds, so
        // x.Type == Int compares identity. A type's own .Type is Function.
        // A lazy sequence's .Type is Sequence (round 41); an enum
        // value's is its enum type (round 45).
        if case .enumCase(let ev) = receiver {
            return .function(ev.type.constructor!)
        }
        if case .structValue(let sv) = receiver {
            return .function(sv.type.constructor!)
        }
        return .function(Builtins.types[receiver.typeName]
                         ?? Builtins.protocols[receiver.typeName]!)
    case ("name", false):
        // Functions are anonymous, but constructors MUST have a .name
        // (round 40) — protocols carry theirs too; a plain {} has nil.
        guard case .function(let f) = receiver else {
            throw SwiftalkError.unknownMember("\(receiver.typeName).name")
        }
        switch f.role {
        case .type(let n), .protocol(let n): return .string(n)
        case .enumType(let et):              return .string(et.name)
        case .structType(let st):            return .string(st.name)
        case .plain, .todo:                  return .nil
        }
    case ("count", false):
        switch receiver {
        case .array(let a):      return .int(Int64(a.count))
        case .string(let s):     return .int(Int64(s.count))   // graphemes (§11)
        case .dictionary(let d): return .int(Int64(d.count))
        case .range(let lower, let upper, let closed):
            return .int(try rangeCount(from: lower, to: upper, closed: closed))
        case .sequence:
            throw SwiftalkError.type(
                "a Sequence may be infinite — take .prefix(n) or .Array() it deliberately")
        default:
            throw SwiftalkError.unknownMember("\(receiver.typeName).count")
        }
    case ("Array", true):
        // §3d converter doubling as the Sequence materializer:
        // seq.Array() collects any Sequence's elements eagerly.
        guard args.isEmpty else {
            throw SwiftalkError.type(".Array() takes no arguments")
        }
        return .array(try collect(receiver))
    case ("prefix", true):
        // The lazy world's terminal (round 41): materialize the first n.
        guard args.count == 1, case .int(let n) = args[0], n >= 0 else {
            throw SwiftalkError.type(".prefix(n) takes one non-negative Int")
        }
        var out: [Value] = []
        let it = try iterator(of: receiver)
        while out.count < Int(n), let element = try it.next() {
            out.append(element)
        }
        return .array(out)
    case ("description", false):
        // print's form: Strings bare, everything else source form.
        return .string(displayString(receiver))
    case ("debugDescription", false):
        // debugPrint's form: quoted strings, hex numbers (round 37).
        return .string(receiver.sourceString(debug: true))
    case ("map", true):
        guard args.count == 1, case .function(let fn) = args[0] else {
            throw SwiftalkError.type(".map takes a single Function")
        }
        // Lazy by default on Sequence values (round 41): map defers.
        if case .sequence(let base) = receiver {
            return .sequence(SequenceObject(kind: .mapped(base, fn)))
        }
        var out: [Value] = []
        let it = try iterator(of: receiver)
        while let element = try it.next() {
            out.append(try apply(fn, args: [(nil, element)]))
        }
        return .array(out)
    case ("filter", true):
        guard args.count == 1, case .function(let fn) = args[0] else {
            throw SwiftalkError.type(".filter takes a single Function")
        }
        // Lazy by default on Sequence values (round 41): filter defers.
        if case .sequence(let base) = receiver {
            return .sequence(SequenceObject(kind: .filtered(base, fn)))
        }
        var kept: [Value] = []
        let it = try iterator(of: receiver)
        while let element = try it.next() {
            guard case .bool(let keep) = try apply(fn, args: [(nil, element)]) else {
                throw SwiftalkError.type("the .filter Function must return a Bool")
            }
            if keep { kept.append(element) }
        }
        switch receiver {
        case .string:
            // Swift-compatible: String.filter gives back a String.
            return .string(kept.map { if case .string(let s) = $0 { s } else { "" } }.joined())
        case .dictionary:
            // Swift-compatible: Dictionary.filter gives back a Dictionary.
            var d: [Value: Value] = [:]
            for pair in kept {
                if case .array(let kv) = pair, kv.count == 2 { d[kv[0]] = kv[1] }
            }
            return .dictionary(d)
        default:
            return .array(kept)
        }
    case ("reduce", true):
        guard args.count == 2, case .function(let fn) = args[1] else {
            throw SwiftalkError.type(".reduce takes an initial value and a Function")
        }
        var accumulator = args[0]
        let it = try iterator(of: receiver)
        while let element = try it.next() {
            accumulator = try apply(fn, args: [(nil, accumulator), (nil, element)])
        }
        return accumulator
    case ("has", true):
        // Presence, distinct from value (round 35): d.has(k) is true for
        // a key holding nil, false for a missing key — the question
        // d[k] cannot answer.
        guard case .dictionary(let d) = receiver else {
            throw SwiftalkError.unknownMember("\(receiver.typeName).has()")
        }
        guard args.count == 1 else {
            throw SwiftalkError.type(".has(key) takes exactly one argument")
        }
        return .bool(d[args[0]] != nil)
    default:
        throw SwiftalkError.unknownMember("\(receiver.typeName).\(name)\(called ? "()" : "")")
    }
}
