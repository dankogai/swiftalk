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
        /// The cooperative scheduler (§12, round 53): tasks spawned in
        /// one eval persist — parked — into the next (the REPL's world).
        private let scheduler = Scheduler()

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

        deinit {
            // Wake every parked task into an unwind so its thread exits.
            scheduler.shutdown()
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
            declareBuiltin("sleep") { args in
                // sleep(seconds) suspends only the *current* context
                // (§12, round 53) — parked tasks run meanwhile. At the
                // top level it doubles as "run the loop for a while".
                let seconds: Double
                switch (args.count, args.first) {
                case (1, .double(let d)?) where d >= 0: seconds = d
                case (1, .int(let i)?) where i >= 0:    seconds = Double(i)
                default:
                    throw SwiftalkError.type("sleep(seconds) — a non-negative Int or Double")
                }
                guard let ctx = Scheduler.current else {
                    throw SwiftalkError.type(
                        "'sleep' inside a Sequence coroutine body is not (yet) supported")
                }
                try ctx.scheduler.sleep(seconds: seconds, from: ctx)
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
            // Result (round 51, §8): a built-in enum, globally bound.
            try! environment.declare("Result", Binding(
                mutable: false,
                lock: TypeAnnotation(name: "Function", optional: false),
                value: .function(Builtins.resultType.constructor!)))
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
            // The top level is the scheduler's main context (round 53:
            // top-level await) — installed thread-locally for the
            // duration, which is all "colorless" costs.
            let previous = Scheduler.activate(scheduler.main)
            defer { Scheduler.restore(previous) }
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
        try checkValue(value, against: lock, context: "'\(name)'")
    }
}

/// Is `value` a Primitive (§3c, rounds 19–20): the scalar roster plus
/// Arrays and Dictionaries thereof — SION-complete minus Data/Date.
func isPrimitives(_ value: Value) -> Bool {
    switch value {
    case .nil, .bool, .int, .double, .string: return true
    case .array(let a):      return a.allSatisfy(isPrimitives)
    case .dictionary(let d): return d.allSatisfy { isPrimitives($0.key) && isPrimitives($0.value) }
    default: return false
    }
}

/// Is `value` SION-serializable (§3b's full roster, round 59):
/// Primitives plus Data and Date, recursively.
func isSION(_ value: Value) -> Bool {
    switch value {
    case .nil, .bool, .int, .double, .string, .data, .date: return true
    case .array(let a):      return a.allSatisfy(isSION)
    case .dictionary(let d): return d.allSatisfy { isSION($0.key) && isSION($0.value) }
    default: return false
    }
}

/// Does `value` satisfy a lock naming `lockName`? Exact type name — or,
/// for a class instance (round 55), any superclass up the chain: a Dog
/// IS an Animal, so `let a: Animal = Dog()` holds.
func typeMatches(_ value: Value, _ lockName: String) -> Bool {
    if value.typeName == lockName { return true }
    if case .actor(let obj) = value {
        var walker = obj.type.superType
        while let current = walker {
            if current.name == lockName { return true }
            walker = current.superType
        }
    }
    return false
}

private let knownTypeNames: Set<String> =
    ["Nil", "Bool", "Int", "Double", "String", "Array", "Dictionary", "Function",
     "Range", "Sequence", "Data", "Date", "Task",
     // Round 59: annotation vocabulary — Any admits everything,
     // Primitives/SION admit their rosters. Not (yet) values.
     "Primitives", "SION", "Any"]

/// A parameterized annotation is known iff its name and every
/// parameter's are (round 59) — `[Int]`, `[String: [Wat]]` checks Wat.
private func annotationIsKnown(_ annotation: TypeAnnotation, in env: Environment) -> Bool {
    (knownTypeNames.contains(annotation.name) || isUserType(annotation.name, in: env))
        && annotation.parameters.allSatisfy { annotationIsKnown($0, in: env) }
}

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
            guard annotationIsKnown(annotation, in: env) || annotatedEnum != nil else {
                throw SwiftalkError.type("unknown type '\(annotation.display)'")
            }
            lock = annotation
        } else {
            // Inference locks to the initializer's runtime type. Bare
            // `var x = nil` has nothing to infer and is rejected (§3a);
            // collections must be homogeneous to infer (round 59).
            guard value != .nil else {
                throw SwiftalkError.type(
                    "cannot infer a type for '\(name)' from nil — annotate it, e.g. \(mutable ? "var" : "let") \(name): Int? = nil")
            }
            lock = try inferLock(value, for: name)
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
                lock: try inferLock(value, for: name),
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
    case .ifLetS(let conditions, let then, let elseBranch):
        // Round 60: bindings must land non-nil (flat optionals — the
        // bound value IS itself, §3a), booleans must hold; left to
        // right, short-circuit, later clauses seeing earlier bindings.
        let scope = Environment(parent: env)
        var pass = true
        loop: for condition in conditions {
            switch condition {
            case .binding(let mutable, let name, let expr):
                let value = try evaluate(expr, in: scope)
                guard value != .nil else {
                    pass = false
                    break loop
                }
                try scope.declare(name, Binding(
                    mutable: mutable,
                    lock: TypeAnnotation(name: value.typeName, optional: false),
                    value: value))
            case .boolean(let expr):
                guard case .bool(let flag) = try evaluate(expr, in: scope) else {
                    throw SwiftalkError.type(
                        "an 'if' condition must be a Bool — nothing is truthy (§3b)")
                }
                guard flag else {
                    pass = false
                    break loop
                }
            }
        }
        if pass {
            try runBlock(then, in: scope)
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
    case .yieldS(let expr):
        // `yield` is dynamic, the Lua way (round 52): it suspends the
        // innermost *running* coroutine — even from a helper function
        // the body called — found through the thread-local.
        let value = try expr.map { try evaluate($0, in: env) } ?? .nil
        guard let runner = CoroutineRunner.current else {
            throw SwiftalkError.type(
                "'yield' outside a coroutine — wrap the function: Sequence(f)")
        }
        try runner.yieldValue(value)
        return .nil
    case .enumDecl(let name, let caseOrder, let cases, let methodExprs):
        let et = EnumType(name: name, caseOrder: caseOrder, cases: cases)
        et.methods = makeMethods(methodExprs, in: env)
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
    case .structDecl(let name, let propertyOrder, let properties, let methodExprs,
                     let initExprs, let computedExprs):
        let st = StructType(name: name, propertyOrder: propertyOrder,
                            properties: properties, declEnv: env)
        st.methods = makeMethods(methodExprs, in: env)
        st.computed = makeComputed(computedExprs, in: env)
        st.observers = makeObservers(propertyOrder, properties, in: env)
        st.inits = initExprs.compactMap {
            guard case .function(let params, let body) = $0 else { return nil }
            return FunctionObject(parameters: params, body: body, closure: env)
        }
        let constructor = FunctionObject(
            parameters: [], body: [], closure: env, builtin: nil,
            role: .structType(st))
        st.constructor = constructor
        try env.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: "Function", optional: false),
            value: .function(constructor)))
        return .function(constructor)
    case .actorDecl(let name, let propertyOrder, let properties, let methodExprs,
                    let initExprs, let computedExprs):
        // Round 54: same declaration machinery as a struct; instances
        // are references, and method calls serialize.
        let at = ActorType(name: name, propertyOrder: propertyOrder,
                           properties: properties, declEnv: env)
        at.methods = makeMethods(methodExprs, in: env)
        at.computed = makeComputed(computedExprs, in: env)
        at.observers = makeObservers(propertyOrder, properties, in: env)
        at.inits = initExprs.compactMap {
            guard case .function(let params, let body) = $0 else { return nil }
            return FunctionObject(parameters: params, body: body, closure: env)
        }
        let actorConstructor = FunctionObject(
            parameters: [], body: [], closure: env, builtin: nil,
            role: .actorType(at))
        at.constructor = actorConstructor
        try env.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: "Function", optional: false),
            value: .function(actorConstructor)))
        return .function(actorConstructor)
    case .classDecl(let name, let superName, let propertyOrder, let properties,
                    let methodExprs, let initExprs, let computedExprs):
        // Round 55: the open reference — an actor minus serialization
        // and isolation, plus single inheritance. Properties merge at
        // declaration (superclass's first, shadowing is an error);
        // methods resolve up the chain at call time (override =
        // redeclare; `super` is OPEN).
        var superType: ActorType? = nil
        if let superName {
            guard let value = try? env.lookup(superName), case .function(let f) = value,
                  case .actorType(let sup) = f.role, !sup.serialized else {
                throw SwiftalkError.type(
                    "a class inherits only from a class — '\(superName)' is not one")
            }
            superType = sup
        }
        var mergedOrder = superType?.propertyOrder ?? []
        var mergedProps = superType?.properties ?? [:]
        for prop in propertyOrder {
            guard mergedProps[prop] == nil else {
                throw SwiftalkError.type(
                    "\(name).\(prop) shadows an inherited property")
            }
            mergedOrder.append(prop)
            mergedProps[prop] = properties[prop]
        }
        let ct = ActorType(name: name, propertyOrder: mergedOrder,
                           properties: mergedProps, declEnv: env,
                           serialized: false, superType: superType)
        // `super` resolves from the class that DECLARED the running
        // method, not from self's dynamic type (round 56) — so the
        // declaring class's superclass is a hidden *lexical* binding
        // in the methods' closure chain (the `@callee` trick again).
        // Bound even when nil, so a nested class never inherits an
        // outer class's `@superclass` by accident.
        let classEnv = Environment(parent: env)
        try classEnv.declare("@superclass", superclassBinding(superType))
        ct.methods = makeMethods(methodExprs, in: classEnv)
        for computedName in computedExprs.keys {
            guard mergedProps[computedName] == nil else {
                throw SwiftalkError.type(
                    "\(name).\(computedName) shadows an inherited property")
            }
        }
        ct.computed = makeComputed(computedExprs, in: classEnv)
        // Own observers (declared props, classEnv so super works) over
        // the superclass's — inherited props keep their observers.
        ct.observers = (superType?.observers ?? [:])
            .merging(makeObservers(propertyOrder, properties, in: classEnv)) { _, own in own }
        ct.inits = initExprs.compactMap {
            guard case .function(let params, let body) = $0 else { return nil }
            return FunctionObject(parameters: params, body: body, closure: classEnv)
        }
        let classConstructor = FunctionObject(
            parameters: [], body: [], closure: env, builtin: nil,
            role: .actorType(ct))
        ct.constructor = classConstructor
        try env.declare(name, Binding(
            mutable: false,
            lock: TypeAnnotation(name: "Function", optional: false),
            value: .function(classConstructor)))
        return .function(classConstructor)
    case .extensionDecl(let typeName, let methodExprs, let computedExprs):
        let fns = makeMethods(methodExprs, in: env)
        guard let value = try? env.lookup(typeName), case .function(let f) = value else {
            throw SwiftalkError.type("unknown type '\(typeName)'")
        }
        switch f.role {
        case .structType(let st):
            for (name, fn) in fns {
                guard st.properties[name] == nil, st.methods[name] == nil,
                      st.computed[name] == nil else {
                    throw SwiftalkError.type("\(typeName) already has a member '\(name)'")
                }
                st.methods[name] = fn
            }
            for (name, c) in makeComputed(computedExprs, in: env) {
                guard st.properties[name] == nil, st.methods[name] == nil,
                      st.computed[name] == nil else {
                    throw SwiftalkError.type("\(typeName) already has a member '\(name)'")
                }
                st.computed[name] = c
            }
        case .enumType(let et):
            guard computedExprs.isEmpty else {
                throw SwiftalkError.type(
                    "computed properties on enums are not (yet) supported")
            }
            for (name, fn) in fns {
                guard et.cases[name] == nil, et.methods[name] == nil else {
                    throw SwiftalkError.type("\(typeName) already has a member '\(name)'")
                }
                et.methods[name] = fn
            }
        case .actorType(let at):
            // A class extension's methods may use `super` (round 56):
            // give them the same lexical @superclass their in-body
            // siblings get. (Actors have none — super errors there.)
            var memberEnv = env
            if !at.serialized {
                let extEnv = Environment(parent: env)
                try extEnv.declare("@superclass", superclassBinding(at.superType))
                memberEnv = extEnv
            }
            let extFns = at.serialized ? fns : makeMethods(methodExprs, in: memberEnv)
            for (name, fn) in extFns {
                guard at.properties[name] == nil, at.methods[name] == nil,
                      at.computed[name] == nil else {
                    throw SwiftalkError.type("\(typeName) already has a member '\(name)'")
                }
                at.methods[name] = fn
            }
            for (name, c) in makeComputed(computedExprs, in: memberEnv) {
                guard at.properties[name] == nil, at.methods[name] == nil,
                      at.computed[name] == nil else {
                    throw SwiftalkError.type("\(typeName) already has a member '\(name)'")
                }
                at.computed[name] = c
            }
        case .type(let n), .protocol(let n):
            // Builtins: hidden env bindings, greppable and scoped (§10's
            // "declared and greppable" discipline for monkey-patching).
            // Computed getters ride the same scheme under "get:" —
            // read-only: a builtin receiver is a value, there is no
            // storage for a setter to reach (round 57).
            for (name, c) in makeComputed(computedExprs, in: env) {
                guard c.set == nil else {
                    throw SwiftalkError.type(
                        "a computed setter on a builtin type is not (yet) supported — \(n).\(name)")
                }
                try env.declare("@ext:\(n):get:\(name)", Binding(
                    mutable: false,
                    lock: TypeAnnotation(name: "Function", optional: false),
                    value: .function(c.get)))
            }
            for (name, fn) in fns {
                try env.declare("@ext:\(n):\(name)", Binding(
                    mutable: false,
                    lock: TypeAnnotation(name: "Function", optional: false),
                    value: .function(fn)))
            }
        case .plain, .todo:
            throw SwiftalkError.type("'\(typeName)' is not a type")
        }
        return .nil
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
    case .enumType, .structType, .actorType: return true
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
        case .coroutine(let body):
            // Round 52: a fresh run of the body per iteration — a
            // Sequence value is re-iterable, like any value. The handle
            // cancels the parked body thread when the pull side walks
            // away (e.g. after `.prefix` of an infinite sequence).
            let handle = CoroutineHandle(CoroutineRunner(body: body))
            return ValueIterator { try handle.next() }
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
        if case .memberLiteral(let name) = callee {
            // Implicit self (round 49): `.method(args)` in a type body...
            if (try? env.lookup("self")) != nil {
                return try evaluateSlow(
                    .method(.variable("self"), name: name, args: args, called: true), in: env)
            }
            // ...else the SION spelling (round 50): `.Date(...)` is
            // `Date(...)` when the name binds a type in scope.
            if case .function(let f)? = try? env.lookup(name) {
                switch f.role {
                case .type, .protocol, .enumType, .structType, .actorType:
                    return try apply(f, args: try evaluateArgs(args, in: env))
                case .plain, .todo:
                    break
                }
            }
        }
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
    case .method(let receiverExpr, let name, let args, let called):
        // super.method(...) (round 56): not a value's member — a
        // lookup pinned to the declaring class's superclass.
        if case .superRef = receiverExpr {
            return try superDispatch(
                name: name,
                args: try args.map { ($0.label, try evaluate($0.expr, in: env)) },
                called: called, env: env)
        }
        let receiver = try evaluate(receiverExpr, in: env)
        let evaluated = try args.map { ($0.label, try evaluate($0.expr, in: env)) }
        if called {
            // Reference-type methods (rounds 54–55): self bound to the
            // reference — mutation is in place, so no write-back dance;
            // actors serialize, classes dispatch up the chain.
            if case .actor(let obj) = receiver, let m = obj.type.lookupMethod(name) {
                return try callActorMethod(obj, m, args: evaluated)
            }
            // Builtin Array mutator (round 49): a.append(x) — the family
            // grows as needed.
            if name == "append", case .array(var a) = receiver {
                guard let target = asLValue(receiverExpr) else {
                    throw SwiftalkError.type("'.append' mutates — call it on a var Array")
                }
                guard !evaluated.isEmpty, evaluated.allSatisfy({ $0.0 == nil }) else {
                    throw SwiftalkError.type(".append takes unlabeled item(s)")
                }
                a.append(contentsOf: evaluated.map(\.1))
                try assign(target, .array(a), in: env)
                return .nil
            }
            // User methods (rounds 48–50): self is always a var; whether
            // the call MAY mutate is the properties' var/let business
            // (round 50 — no `mutating` keyword). If self actually
            // changed, it writes back through the receiver's lvalue —
            // a let receiver or a temporary errors only then.
            var userMethod: FunctionObject? = nil
            if case .structValue(let sv) = receiver, let m = sv.type.methods[name] {
                userMethod = m
            } else if case .enumCase(let ev) = receiver, let m = ev.type.methods[name] {
                userMethod = m
            } else if let m = lookupExtension(env, receiver.typeName, name) {
                userMethod = m
            }
            if let m = userMethod {
                let (bound, selfEnv) = try boundMethod(m, self: receiver, mutableSelf: true)
                let result = try apply(bound, args: evaluated)
                let newSelf = try selfEnv.lookup("self")
                if newSelf != receiver {
                    guard let target = asLValue(receiverExpr) else {
                        throw SwiftalkError.type(
                            "method '\(name)' mutated a temporary — call it on a var")
                    }
                    try assign(target, newSelf, in: env)
                }
                return result
            }
        }
        return try method(on: receiver, name: name, args: evaluated, called: called, env: env)
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
    case .superRef:
        throw SwiftalkError.type("'super' is not a value — call super.method(...)")
    case .memberLiteral(let name):
        // Implicit self first (round 49): inside a type body, `.value`
        // means `self.value`. Otherwise a format member (.quoted, .hex,
        // ...) — provisionally a String until enums back them (round 42).
        if let selfValue = try? env.lookup("self") {
            do {
                return try method(on: selfValue, name: name, args: [], called: false, env: env)
            } catch SwiftalkError.unknownMember {
                // fall through to the format-member reading
            }
        }
        return .string(name)
    case .awaitE(let inner):
        // `await t` (§12, round 53): join a Task — colorless, so this
        // is legal in any function; what matters is the *running
        // context* (main at top level, the task's own inside a task),
        // found through the scheduler's thread-local.
        let value = try evaluate(inner, in: env)
        guard case .task(let task) = value else {
            throw SwiftalkError.type("can only await a Task — got \(value.typeName)")
        }
        guard let ctx = Scheduler.current else {
            throw SwiftalkError.type(
                "'await' inside a Sequence coroutine body is not (yet) supported")
        }
        return try ctx.scheduler.awaitTask(task, from: ctx)
    case .propagate(let inner):
        // Postfix ? (§3a/§8, unified): unwrap .success; early-return
        // .failure or nil from the enclosing function; anything else is
        // already its unwrapped self (flat optionals).
        let v = try evaluate(inner, in: env)
        switch v {
        case .nil:
            throw ReturnSignal(value: .nil)
        case .enumCase(let ev) where ev.type === Builtins.resultType:
            guard ev.caseName == "success" else {
                throw ReturnSignal(value: v)      // the failure propagates whole
            }
            return ev.associated[0]
        default:
            return v
        }
    case .forceUnwrap(let inner):
        // Postfix ! (§3a): for when the scripter is sure — trapping when
        // they were wrong.
        let v = try evaluate(inner, in: env)
        switch v {
        case .nil:
            throw SwiftalkError.type("force-unwrapped nil")
        case .enumCase(let ev) where ev.type === Builtins.resultType:
            guard ev.caseName == "success" else {
                throw SwiftalkError.type(
                    "force-unwrapped a failure: \(ev.associated[0].sourceString())")
            }
            return ev.associated[0]
        default:
            return v
        }
    case .coalesce(let lhs, let rhs):
        // a ?? b: default on absence or failure; the right side stays
        // unevaluated when the left provides.
        switch try evaluate(lhs, in: env) {
        case .nil:
            return try evaluate(rhs, in: env)
        case .enumCase(let ev) where ev.type === Builtins.resultType:
            return ev.caseName == "success" ? ev.associated[0] : try evaluate(rhs, in: env)
        case let v:
            return v
        }
    case .optionalMember(let receiverExpr, let name, let args, let called):
        // a?.b — nil skips the member (arguments unevaluated). Chains of
        // ?. compose; a plain `.` after a nil errors (unlike Swift's
        // whole-chain short-circuit — noted divergence).
        let receiver = try evaluate(receiverExpr, in: env)
        if receiver == .nil { return .nil }
        return try evaluateSlow(
            .method(.literal(receiver), name: name, args: args, called: called), in: env)
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
    case .data(let bytes):
        guard case .int(let i) = index else {
            throw SwiftalkError.type("Data index must be an Int, not \(index.typeName)")
        }
        guard bytes.indices.contains(Int(i)) else {
            throw SwiftalkError.type("index \(i) out of range (count \(bytes.count))")
        }
        return .int(Int64(bytes[Int(i)]))
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
    case .memberLiteral(let name):
        // Implicit self (round 49): `.value` is an lvalue on self.
        return .property(.variable("self"), name)
    default:
        return nil
    }
}

/// Turns parsed computed-property specs into runnable getter/setter
/// pairs closed over the declaring environment (round 57).
private func makeComputed(_ exprs: [String: ComputedSpec],
                          in env: Environment) -> [String: ComputedProperty] {
    var out: [String: ComputedProperty] = [:]
    for (name, spec) in exprs {
        guard case .function(let getParams, let getBody) = spec.get else { continue }
        var setter: FunctionObject? = nil
        if case .function(let setParams, let setBody)? = spec.set {
            setter = FunctionObject(parameters: setParams, body: setBody, closure: env)
        }
        out[name] = ComputedProperty(
            annotation: spec.annotation,
            get: FunctionObject(parameters: getParams, body: getBody, closure: env),
            set: setter)
    }
    return out
}

/// The computed property visible on a value, if any (round 57):
/// structs look in their type; references walk the class chain.
func computedProperty(of receiver: Value, _ name: String) -> ComputedProperty? {
    switch receiver {
    case .structValue(let sv): return sv.type.computed[name]
    case .actor(let obj):      return obj.type.lookupComputed(name)
    default:                   return nil
    }
}

/// Runs a computed getter — serialized when the receiver is an actor
/// (a getter is a method); annotation-checked when annotated.
func readComputed(_ c: ComputedProperty, on receiver: Value) throws -> Value {
    let value: Value
    if case .actor(let obj) = receiver {
        value = try callActorMethod(obj, c.get, args: [])
    } else {
        let (bound, _) = try boundMethod(c.get, self: receiver)
        value = try apply(bound, args: [])
    }
    if let annotation = c.annotation {
        try checkValue(value, against: annotation,
                       context: "computed \(receiver.typeName) property")
    }
    return value
}

/// Runs a computed setter; returns the (possibly rebuilt) receiver —
/// value semantics for structs, the same reference for actor/class.
/// An actor's setter is the actor's own code: allowed from anywhere,
/// and serialized like any method (the isolation story holds).
func writeComputed(_ c: ComputedProperty, on receiver: Value, name: String,
                   newValue: Value) throws -> Value {
    guard let setter = c.set else {
        throw SwiftalkError.type(
            "\(receiver.typeName).\(name) is a read-only computed property")
    }
    if let annotation = c.annotation {
        try checkValue(newValue, against: annotation,
                       context: "\(receiver.typeName).\(name)")
    }
    if case .actor(let obj) = receiver {
        _ = try callActorMethod(obj, setter, args: [(nil, newValue)])
        return receiver
    }
    let (bound, selfEnv) = try boundMethod(setter, self: receiver, mutableSelf: true)
    _ = try apply(bound, args: [(nil, newValue)])
    return try selfEnv.lookup("self")
}

/// Builds runnable observers for the properties that declared any
/// (round 58b), closed over the declaring environment.
private func makeObservers(_ order: [String],
                           _ props: [String: StructType.Property],
                           in env: Environment) -> [String: PropertyObservers] {
    var out: [String: PropertyObservers] = [:]
    for name in order {
        guard let p = props[name], p.willSetExpr != nil || p.didSetExpr != nil else { continue }
        func build(_ expr: Expr?) -> FunctionObject? {
            guard case .function(let params, let body)? = expr else { return nil }
            return FunctionObject(parameters: params, body: body, closure: env)
        }
        out[name] = PropertyObservers(will: build(p.willSetExpr), did: build(p.didSetExpr))
    }
    return out
}

/// Turns parsed method expressions into FunctionObjects closed over the
/// declaring environment (round 48).
private func makeMethods(_ exprs: [String: Expr], in env: Environment) -> [String: FunctionObject] {
    var out: [String: FunctionObject] = [:]
    for (name, expr) in exprs {
        guard case .function(let params, let body) = expr else { continue }
        out[name] = FunctionObject(parameters: params, body: body, closure: env)
    }
    return out
}

/// Extension methods on builtin types live as hidden env bindings
/// (`@` cannot appear in identifiers); user types carry theirs
/// directly.
func lookupExtension(_ env: Environment, _ typeName: String, _ name: String) -> FunctionObject? {
    guard let value = try? env.lookup("@ext:\(typeName):\(name)"),
          case .function(let fn) = value else { return nil }
    return fn
}

/// Binds `self` for a method invocation (round 48): a fresh scope
/// between the method's lexical home and its locals.
func boundMethod(_ method: FunctionObject, self receiver: Value,
                 mutableSelf: Bool = false) throws -> (FunctionObject, Environment) {
    let selfEnv = Environment(parent: method.closure)
    try selfEnv.declare("self", Binding(
        mutable: mutableSelf,
        lock: TypeAnnotation(name: receiver.typeName, optional: false),
        value: receiver))
    return (FunctionObject(parameters: method.parameters, body: method.body,
                           closure: selfEnv), selfEnv)
}

/// Does a declared init accept this argument list? Multi-dispatch
/// (round 48): arity + labels; a param-less init is variadic (round
/// 14), so it matches anything — declare it last.
private func initMatches(_ params: [String], _ args: [(label: String?, value: Value)]) -> Bool {
    if params.isEmpty { return true }
    guard args.count == params.count else { return false }
    var used = Set<String>()
    for (label, _) in args {
        if let label {
            guard params.contains(label), !used.contains(label) else { return false }
            used.insert(label)
        }
    }
    return true
}

/// The memberwise initializer (round 46): labels optional and
/// reorderable per §2.3, positionals fill in declaration order,
/// missing properties take their defaults (evaluated in the struct's
/// declaring environment), annotations checked per §3.
func constructStruct(_ st: StructType,
                     args: [(label: String?, value: Value)]) throws -> Value {
    // Declared inits multi-dispatch first (round 48): the first match
    // wins; the memberwise init below is the last candidate.
    for initFn in st.inits where initMatches(initFn.parameters, args) {
        var values: [String: Value] = [:]
        for prop in st.propertyOrder {
            values[prop] = try st.properties[prop]!.defaultExpr.map {
                try evaluate($0, in: Environment(parent: st.declEnv))
            } ?? .nil
        }
        let underConstruction = Value.structValue(StructValue(type: st, values: values))
        let (fn, selfEnv) = try boundMethod(initFn, self: underConstruction, mutableSelf: true)
        // Observers stay silent during init (round 58b, Swift's rule).
        let claimed = ObserverGuard.enter(all: st.observers.keys.map { "\(st.name).\($0)" })
        defer { ObserverGuard.leave(all: claimed) }
        _ = try apply(fn, args: args)
        guard case .structValue(let sv) = try selfEnv.lookup("self") else {
            fatalError("unreachable")
        }
        for prop in st.propertyOrder {
            if let annotation = st.properties[prop]!.annotation, !annotation.optional,
               annotation.name != "Nil", sv.values[prop] == .nil {
                throw SwiftalkError.type(
                    "\(st.name).\(prop) was not initialized by init")
            }
        }
        return .structValue(sv)
    }
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

/// Constructs an actor instance (round 54): the struct construction
/// story — declared inits multi-dispatch, memberwise last, defaults
/// prefilled, post-init nil verification — except the result is born a
/// reference and init writes mutate it in place (no acquire needed:
/// nobody else can hold a reference yet).
func constructActor(_ at: ActorType,
                    args: [(label: String?, value: Value)]) throws -> Value {
    func defaults() throws -> [String: Value] {
        var storage: [String: Value] = [:]
        for prop in at.propertyOrder {
            storage[prop] = try at.properties[prop]!.defaultExpr.map {
                try evaluate($0, in: Environment(parent: at.declEnv))
            } ?? .nil
        }
        return storage
    }
    for initFn in at.inits where initMatches(initFn.parameters, args) {
        let obj = ActorObject(type: at, storage: try defaults())
        let (fn, _) = try boundMethod(initFn, self: .actor(obj))
        // Observers stay silent during init (round 58b, Swift's rule).
        let claimed = ObserverGuard.enter(
            all: at.observers.keys.map { "\(ObjectIdentifier(obj)).\($0)" })
        defer { ObserverGuard.leave(all: claimed) }
        _ = try apply(fn, args: args)
        for prop in at.propertyOrder {
            if let annotation = at.properties[prop]!.annotation, !annotation.optional,
               annotation.name != "Nil", obj.storage[prop] == .nil {
                throw SwiftalkError.type("\(at.name).\(prop) was not initialized by init")
            }
        }
        return .actor(obj)
    }
    var slots: [String: Value] = [:]
    var positionals: [Value] = []
    for (label, value) in args {
        if let label {
            guard at.properties[label] != nil else {
                throw SwiftalkError.type("\(at.name) has no property '\(label)'")
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
    var storage: [String: Value] = [:]
    for prop in at.propertyOrder {
        let def = at.properties[prop]!
        let value: Value
        if let given = slots[prop] {
            value = given
        } else if !remaining.isEmpty {
            value = remaining.removeFirst()
        } else if let defaultExpr = def.defaultExpr {
            value = try evaluate(defaultExpr, in: Environment(parent: at.declEnv))
        } else {
            throw SwiftalkError.type("missing property '\(prop)' of \(at.name)")
        }
        if let annotation = def.annotation {
            try checkValue(value, against: annotation, context: "\(at.name).\(prop)")
        }
        storage[prop] = value
    }
    guard remaining.isEmpty else {
        throw SwiftalkError.type("too many values for \(at.name)")
    }
    return .actor(ActorObject(type: at, storage: storage))
}

/// Calls an actor method (round 54): acquire — colorless, parking the
/// caller if another context is inside — run with `self` bound to the
/// reference, release on the way out (error or not). Held to the end:
/// suspensions inside the body do NOT release (the anti-reentrancy
/// divergence from Swift); a circular wait becomes a deadlock error.
func callActorMethod(_ obj: ActorObject, _ method: FunctionObject,
                     args: [(label: String?, value: Value)]) throws -> Value {
    // A class method (round 55) is just a call: no baton, no queue —
    // which also means classes work fine inside coroutine bodies.
    guard obj.type.serialized else {
        let (bound, _) = try boundMethod(method, self: .actor(obj))
        return try apply(bound, args: args)
    }
    guard let ctx = Scheduler.current else {
        throw SwiftalkError.type(
            "actor methods need a task or top-level context — not (yet) inside a Sequence coroutine body")
    }
    try ctx.scheduler.acquire(obj, from: ctx)
    defer { ctx.scheduler.release(obj, from: ctx) }
    let (bound, _) = try boundMethod(method, self: .actor(obj))
    return try apply(bound, args: args)
}

/// The hidden lexical binding through which `super` finds the
/// declaring class's superclass (round 56). Bound to nil for a root
/// class, so `super` there says so instead of finding an outer one.
func superclassBinding(_ superType: ActorType?) -> Binding {
    Binding(mutable: false,
            lock: TypeAnnotation(name: superType == nil ? "Nil" : "Function",
                                 optional: superType == nil),
            value: superType.map { .function($0.constructor!) } ?? .nil)
}

/// `super.name(...)` (round 56) — class-only, by construction: super
/// goes where OVERRIDE goes, override exists only where inheritance
/// does, and inheritance is class-only (§4). The lookup starts at the
/// *declaring* class's superclass (the lexical `@superclass`), never
/// at self's dynamic type — a three-level chain must not loop. `self`
/// stays dynamic inside the super-dispatched body, as in Swift.
private func superDispatch(name: String, args: [(label: String?, value: Value)],
                           called: Bool, env: Environment) throws -> Value {
    guard case .actor(let obj)? = try? env.lookup("self"),
          let marker = try? env.lookup("@superclass") else {
        throw SwiftalkError.type("'super' works inside a class method")
    }
    guard case .function(let f) = marker, case .actorType(let sup) = f.role else {
        throw SwiftalkError.type(
            "\(obj.type.name) has no superclass — 'super' has nothing to reach")
    }
    if name == "init" {
        // super.init(...) runs a DECLARED superclass init on self —
        // multi-dispatch, round-48 style. (No declared init to reach:
        // memberwise initialization already ran before yours did.)
        guard called else {
            throw SwiftalkError.type("super.init is called: super.init(...)")
        }
        for initFn in sup.inits where initMatches(initFn.parameters, args) {
            let (bound, _) = try boundMethod(initFn, self: .actor(obj))
            return try apply(bound, args: args)
        }
        throw SwiftalkError.type(
            "\(sup.name) declares no init matching these arguments — properties are memberwise-prefilled; assign self.… directly")
    }
    // A computed property the override covered (round 57): run the
    // superclass's getter on self. (super is class-only — no baton.)
    if let c = sup.lookupComputed(name) {
        let (bound, _) = try boundMethod(c.get, self: .actor(obj))
        let value = try apply(bound, args: [])
        if !called { return value }
        guard case .function(let fn) = value else {
            throw SwiftalkError.type(
                "cannot call \(sup.name).\(name), a \(value.typeName)")
        }
        return try apply(fn, args: args)
    }
    guard let m = sup.lookupMethod(name) else {
        if sup.properties[name] != nil {
            throw SwiftalkError.type(
                "'super' reaches methods — properties are never overridden; read self.\(name)")
        }
        throw SwiftalkError.unknownMember("\(sup.name).\(name)")
    }
    let (bound, _) = try boundMethod(m, self: .actor(obj))
    return called ? try apply(bound, args: args) : .function(bound)
}

/// Reads an actor property — open to everyone (atomic under the baton).
func actorRead(_ obj: ActorObject, _ name: String) throws -> Value {
    if let c = obj.type.lookupComputed(name) {
        return try readComputed(c, on: .actor(obj))
    }
    guard let value = obj.storage[name] else {
        throw SwiftalkError.unknownMember("\(obj.type.name).\(name)")
    }
    return value
}

/// Writes an actor property, in place — round 54's isolation: only the
/// actor's own methods (any scope whose `self` IS this actor) may
/// mutate; the property's var/let and type lock still govern, as ever.
func actorWrite(_ obj: ActorObject, _ name: String, _ newValue: Value,
                in env: Environment) throws {
    // A computed setter (round 57) is the type's OWN code — so it runs
    // from anywhere, before the isolation gate, serialized on actors.
    if let c = obj.type.lookupComputed(name) {
        _ = try writeComputed(c, on: .actor(obj), name: name, newValue: newValue)
        return
    }
    // Isolation is the actor's (round 54); a class (round 55) is the
    // open reference — anyone may write, var/let still governing.
    if obj.type.serialized {
        guard case .actor(let selfObj)? = try? env.lookup("self"), selfObj === obj else {
            throw SwiftalkError.type(
                "an actor's state is mutated only by its own methods — \(obj.type.name).\(name) is isolated")
        }
    }
    guard let def = obj.type.properties[name], let current = obj.storage[name] else {
        throw SwiftalkError.unknownMember("\(obj.type.name).\(name)")
    }
    guard def.mutable else {
        throw SwiftalkError.type("cannot assign to let property '\(obj.type.name).\(name)'")
    }
    if let annotation = def.annotation {
        try checkValue(newValue, against: annotation, context: "\(obj.type.name).\(name)")
    } else if current != .nil, newValue.typeName != current.typeName {
        throw SwiftalkError.type(
            "cannot assign \(newValue.typeName) to \(obj.type.name).\(name) of type \(current.typeName)")
    }
    // Observers (round 58b) — reference edition: in-place, keyed by
    // identity, guarded against re-entrant self-assignment. No extra
    // serialization: an actor write is already inside its methods.
    let guardKey = "\(ObjectIdentifier(obj)).\(name)"
    guard let observers = obj.type.observers[name], ObserverGuard.enter(guardKey) else {
        obj.storage[name] = newValue
        return
    }
    defer { ObserverGuard.leave(guardKey) }
    if let will = observers.will {
        let (bound, _) = try boundMethod(will, self: .actor(obj))
        _ = try apply(bound, args: [(nil, newValue)])
    }
    obj.storage[name] = newValue
    if let did = observers.did {
        let (bound, _) = try boundMethod(did, self: .actor(obj))
        _ = try apply(bound, args: [(nil, current)])
    }
}

/// The §3 lock check, standalone (shared by bindings and properties).
/// Round 59 additions: `Any` admits everything, `Primitives`/`SION`
/// admit their rosters (nil included — nil IS a Primitive), and
/// parameterized locks (`[Int]`, `[String: Int]`) check elements,
/// keys, and values recursively. Per round 35, a Dictionary's values
/// are implicitly optional — nil is a right value for a key.
func checkValue(_ value: Value, against lock: TypeAnnotation, context: String) throws {
    if case .nil = value {
        guard lock.optional || lock.name == "Nil" || lock.name == "Any"
                || lock.name == "Primitives" || lock.name == "SION" else {
            throw SwiftalkError.type(
                "cannot assign nil to \(context) of type \(lock.display) — declare it \(lock.display)?")
        }
        return
    }
    switch lock.name {
    case "Any":
        return
    case "Primitives":
        guard isPrimitives(value) else {
            throw SwiftalkError.type(
                "cannot assign \(value.typeName) to \(context) of type Primitives")
        }
        return
    case "SION":
        guard isSION(value) else {
            throw SwiftalkError.type(
                "cannot assign \(value.typeName) to \(context) of type SION")
        }
        return
    default:
        break
    }
    guard typeMatches(value, lock.name) else {
        throw SwiftalkError.type(
            "cannot assign \(value.typeName) to \(context) of type \(lock.display)")
    }
    if lock.name == "Array", lock.parameters.count == 1, case .array(let a) = value {
        for (index, element) in a.enumerated() {
            try checkValue(element, against: lock.parameters[0], context: "\(context)[\(index)]")
        }
    }
    if lock.name == "Dictionary", lock.parameters.count == 2, case .dictionary(let d) = value {
        for (key, val) in d {
            try checkValue(key, against: lock.parameters[0], context: "a key of \(context)")
            if val != .nil {
                try checkValue(val, against: lock.parameters[1],
                               context: "\(context)[\(key.sourceString())]")
            }
        }
    }
}

/// Infers the lock a binding takes from its initializer (round 59):
/// scalars lock to their type as ever; an Array must be HOMOGENEOUS —
/// `[0, 1, 2]` is `[Int]`, `[0.0, 1, 2]` is an error unless annotated
/// (`[Primitives]`, `SION`, or `Any`); a Dictionary infers `[K: V]`
/// from homogeneous keys and non-nil values (a sparse array is a
/// Dictionary, like JS and PHP — round 59's own words).
func inferLock(_ value: Value, for name: String) throws -> TypeAnnotation {
    switch value {
    case .array(let a):
        guard !a.isEmpty else { return TypeAnnotation(name: "Array", optional: false) }
        var element: TypeAnnotation? = nil
        for v in a {
            guard v != .nil else {
                throw SwiftalkError.type(
                    "cannot infer an element type for '\(name)' from a nil element — annotate it, e.g. [Int?]")
            }
            let t = try inferLock(v, for: name)
            if let element, element != t {
                throw SwiftalkError.type(
                    "cannot infer one element type for '\(name)' (\(element.display) vs \(t.display)) — annotate it: [Primitives], SION, or Any")
            }
            element = t
        }
        return TypeAnnotation(name: "Array", optional: false, parameters: [element!])
    case .dictionary(let d):
        guard !d.isEmpty else { return TypeAnnotation(name: "Dictionary", optional: false) }
        var key: TypeAnnotation? = nil
        var val: TypeAnnotation? = nil
        for (k, v) in d {
            let kt = try inferLock(k, for: name)
            if let key, key != kt {
                throw SwiftalkError.type(
                    "cannot infer one key type for '\(name)' (\(key.display) vs \(kt.display)) — annotate it, e.g. [Primitives: Any]")
            }
            key = kt
            guard v != .nil else { continue }        // round 35: nil shapes nothing
            let vt = try inferLock(v, for: name)
            if let val, val != vt {
                throw SwiftalkError.type(
                    "cannot infer one value type for '\(name)' (\(val.display) vs \(vt.display)) — annotate it, e.g. [\(key!.display): Any]")
            }
            val = vt
        }
        guard let key, let val else {
            throw SwiftalkError.type(
                "cannot infer a value type for '\(name)' — every value is nil; annotate it, e.g. [\(key?.display ?? "Int"): Int?]")
        }
        return TypeAnnotation(name: "Dictionary", optional: false, parameters: [key, val])
    default:
        return TypeAnnotation(name: value.typeName, optional: false)
    }
}

/// Reads a struct property (assignment paths; expression reads go
/// through `method()`).
private func propertyRead(_ container: Value, _ name: String) throws -> Value {
    guard case .structValue(let sv) = container else {
        throw SwiftalkError.type("cannot assign through a property of \(container.typeName)")
    }
    if let c = sv.type.computed[name] {
        return try readComputed(c, on: container)      // get-modify-set paths
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
    if let c = sv.type.computed[name] {
        return try writeComputed(c, on: container, name: name, newValue: newValue)
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
    // Observers (round 58b): willSet before the store (self still
    // old), didSet after (self new, and it may clamp — its self
    // writes back). The guard cuts re-entrancy: a didSet assigning
    // its own property stores directly instead of recursing.
    let guardKey = "\(sv.type.name).\(name)"
    guard let observers = sv.type.observers[name], ObserverGuard.enter(guardKey) else {
        sv.values[name] = newValue
        return .structValue(sv)
    }
    defer { ObserverGuard.leave(guardKey) }
    if let will = observers.will {
        let (bound, _) = try boundMethod(will, self: .structValue(sv))
        _ = try apply(bound, args: [(nil, newValue)])
    }
    sv.values[name] = newValue
    if let did = observers.did {
        let (bound, selfEnv) = try boundMethod(did, self: .structValue(sv), mutableSelf: true)
        _ = try apply(bound, args: [(nil, current)])
        return try selfEnv.lookup("self")
    }
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
    // Rebuild is COW — except through an actor (round 54): a reference
    // mutates in place, and the rebuild STOPS there (the reference
    // itself never changed, so outer containers and the root binding —
    // even a `let` — are untouched, as with Swift's class references).
    func rebuild(_ container: Value, _ depth: Int) throws -> (Value, inPlace: Bool) {
        if case .actor(let obj) = container {
            guard case .property(let p) = steps[depth] else {
                throw SwiftalkError.type("\(obj.type.name) has no subscripts")
            }
            if depth == steps.count - 1 {
                try actorWrite(obj, p, value, in: env)
            } else {
                let inner = try actorRead(obj, p)
                let (newInner, done) = try rebuild(inner, depth + 1)
                if !done { try actorWrite(obj, p, newInner, in: env) }
            }
            return (container, true)
        }
        if depth == steps.count - 1 {
            return (try write(container, steps[depth], value), false)
        }
        let inner = try read(container, steps[depth])
        let (newInner, done) = try rebuild(inner, depth + 1)
        if done { return (container, true) }
        return (try write(container, steps[depth], newInner), false)
    }
    let (rebuilt, inPlace) = try rebuild(try env.lookup(name), 0)
    if !inPlace {
        try env.assign(name, rebuilt)
    }
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
    // Calling an actor type constructs a fresh reference (round 54).
    if case .actorType(let at) = fn.role {
        return try constructActor(at, args: args)
    }
    // The round-47 law, constructor side: TypeName(x, tag: ...) is
    // x.TypeName(tag: ...) — the first unlabeled argument is the
    // subject, the rest are format arguments.
    if case .type(let typeName) = fn.role {
        var subject: Value? = nil
        var extra: [(label: String?, value: Value)] = []
        for (index, arg) in args.enumerated() {
            if index == 0, arg.label == nil {
                subject = arg.value
            } else {
                extra.append(arg)
            }
        }
        return try convert(typeName, subject: subject, extra: extra)
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
        case (.date(let a), .date(let b)):     ascending = a < b   // Comparable (round 50)
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
/// The one conversion behind both spellings (round 47):
/// `x.TypeName(tag: ...)` and `TypeName(x, tag: ...)` land here alike.
/// No extras → the plain constructor; extras are format arguments
/// (String's formats; Sequence's generator closure).
func convert(_ typeName: String, subject: Value?,
             extra: [(label: String?, value: Value)]) throws -> Value {
    let object = (Builtins.types[typeName] ?? Builtins.protocols[typeName])!
    if extra.isEmpty {
        return try object.builtin!(subject.map { [$0] } ?? [])
    }
    switch typeName {
    case "String":
        guard let subject else {
            throw SwiftalkError.type("String formats need a value to format")
        }
        return try stringFormat(subject, extra)
    case "Sequence":
        // state.Sequence { next } == Sequence(state) { next } — the law's
        // bonus: trailing-closure generator construction.
        guard let subject, extra.count == 1, extra[0].label == nil else {
            throw SwiftalkError.type("Sequence(initialState) { next } — an Array state and a Function")
        }
        return try object.builtin!([subject, extra[0].value])
    default:
        throw SwiftalkError.type("\(typeName)() takes no format arguments")
    }
}

/// String's format vocabulary (rounds 20–21, 42): .quoted, .hex/.oct/
/// .bin (prefixed, literal-ready), radix: n (bare digits).
private func stringFormat(_ subject: Value,
                          _ formats: [(label: String?, value: Value)]) throws -> Value {
    guard formats.count == 1 else {
        throw SwiftalkError.type(".String() takes at most one format argument")
    }
    let (label, format) = formats[0]
    if label == "radix" {
        guard case .int(let radix) = format, (2...36).contains(radix) else {
            throw SwiftalkError.type(".String(radix:) takes an Int in 2...36")
        }
        guard case .int(let i) = subject else {
            throw SwiftalkError.type(".String(radix:) is an Int's format")
        }
        return .string(String(i, radix: Int(radix)))
    }
    guard label == nil else {
        throw SwiftalkError.type("unknown .String() format label '\(label!)'")
    }
    switch format {
    case .string("quoted"):
        return .string(subject.sourceString())
    case .string("utf8"):
        // data.String(.utf8) — the failable decode (§3d, round 23):
        // bytes may not be valid text, so nil when they aren't.
        guard case .data(let bytes) = subject else {
            throw SwiftalkError.type(".String(.utf8) decodes Data")
        }
        var decoder = UTF8()
        var iterator = bytes.makeIterator()
        var out = ""
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): out.unicodeScalars.append(scalar)
            case .emptyInput:              return .string(out)
            case .error:                   return .nil
            }
        }
    case .string("hex"):
        // Literal-ready, prefixed — round-trips (rounds 20–21).
        switch subject {
        case .int:            return .string(subject.sourceString(debug: true))
        case .double(let d):  return .string(Value.hexFloat(d))
        default:
            throw SwiftalkError.type(".String(.hex) is a number's format")
        }
    case .string("oct"), .string("bin"):
        guard case .int(let i) = subject else {
            throw SwiftalkError.type(".String(.oct)/.String(.bin) are an Int's formats")
        }
        let (prefix, radix) = format == .string("oct") ? ("0o", 8) : ("0b", 2)
        return .string((i < 0 ? "-" : "") + prefix + String(i.magnitude, radix: radix))
    default:
        throw SwiftalkError.type("unknown .String() format \(format.sourceString())")
    }
}

/// Rejects labeled arguments where a member takes none, yielding the
/// bare values.
private func plainValues(_ args: [(label: String?, value: Value)], for member: String) throws -> [Value] {
    if let label = args.compactMap(\.label).first {
        throw SwiftalkError.type("\(member) takes no argument label '\(label)'")
    }
    return args.map(\.value)
}

private func method(on receiver: Value, name: String,
                    args labeledArgs: [(label: String?, value: Value)], called: Bool,
                    env: Environment) throws -> Value {
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
        case .enumType, .structType, .actorType:
            // User types get synthesized Equatable/Hashable (§10) —
            // an actor's by identity, like Function.
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
    // Computed properties (round 57): the paren-less read user types
    // lacked — a read runs the getter; `p.f()` on one that returned a
    // Function calls through, like a stored Function.
    if let c = computedProperty(of: receiver, name) {
        let value = try readComputed(c, on: receiver)
        if !called { return value }
        guard case .function(let fn) = value else {
            throw SwiftalkError.type(
                "cannot call \(receiver.typeName).\(name), a \(value.typeName)")
        }
        return try apply(fn, args: labeledArgs)
    }
    // Actor members (round 54). Property reads are open — atomic under
    // the baton; stored Functions call through like a struct's.
    if case .actor(let obj) = receiver, let value = obj.storage[name] {
        if !called { return value }
        guard case .function(let fn) = value else {
            throw SwiftalkError.type("cannot call \(obj.type.name).\(name), a \(value.typeName)")
        }
        return try apply(fn, args: labeledArgs)
    }
    // Actor methods: called (the ?. path lands here) — serialized; an
    // uncalled extraction gets a wrapper so serialization survives the
    // trip (`let f = a.inc; f()` still queues like a direct call).
    if case .actor(let obj) = receiver, let m = obj.type.lookupMethod(name) {
        if called { return try callActorMethod(obj, m, args: labeledArgs) }
        return .function(FunctionObject(
            parameters: m.parameters, body: [], closure: Builtins.emptyEnvironment,
            builtin: { ordered in
                try callActorMethod(obj, m, args: ordered.map { (nil, $0) })
            }))
    }
    // Struct property reads (round 46): p.x — and p.f() when the
    // property stores a Function (round 48).
    if case .structValue(let sv) = receiver, let value = sv.values[name] {
        if !called { return value }
        guard case .function(let fn) = value else {
            throw SwiftalkError.type("cannot call \(sv.type.name).\(name), a \(value.typeName)")
        }
        return try apply(fn, args: labeledArgs)
    }
    // User-type/extension methods, uncalled path (rounds 48–50): the
    // bound Function closes over a COPY of self — value semantics; its
    // later mutations stay in the copy. (Calls route through evaluate's
    // dispatch, which write-backs actual mutation.)
    if case .structValue(let sv) = receiver, let m = sv.type.methods[name] {
        let (bound, _) = try boundMethod(m, self: receiver, mutableSelf: true)
        return called ? try apply(bound, args: labeledArgs) : .function(bound)
    }
    if case .enumCase(let ev) = receiver, let m = ev.type.methods[name] {
        let (bound, _) = try boundMethod(m, self: receiver, mutableSelf: true)
        return called ? try apply(bound, args: labeledArgs) : .function(bound)
    }
    if let m = lookupExtension(env, receiver.typeName, name) {
        let (bound, _) = try boundMethod(m, self: receiver, mutableSelf: true)
        return called ? try apply(bound, args: labeledArgs) : .function(bound)
    }
    // Builtin-extension computed getters (round 57): read-only —
    // `extension Int { var doubled { self * 2 } }` → `21.doubled`.
    if let g = lookupExtension(env, receiver.typeName, "get:\(name)") {
        let (bound, _) = try boundMethod(g, self: receiver)
        let value = try apply(bound, args: [])
        if !called { return value }
        guard case .function(let fn) = value else {
            throw SwiftalkError.type(
                "cannot call \(receiver.typeName).\(name), a \(value.typeName)")
        }
        return try apply(fn, args: labeledArgs)
    }
    // The round-47 law: x.TypeName(tag: ...) is TypeName(x, tag: ...) —
    // one operation, two spellings; the method form chains.
    if called, Builtins.types[name] != nil || Builtins.protocols[name] != nil {
        return try convert(name, subject: receiver, extra: labeledArgs)
    }
    let args = try plainValues(labeledArgs, for: ".\(name)")
    switch (name, called) {
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
        if case .actor(let obj) = receiver {
            return .function(obj.type.constructor!)
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
        case .actorType(let at):             return .string(at.name)
        case .plain, .todo:                  return .nil
        }
    case ("count", false):
        switch receiver {
        case .array(let a):      return .int(Int64(a.count))
        case .string(let s):     return .int(Int64(s.count))   // graphemes (§11)
        case .dictionary(let d): return .int(Int64(d.count))
        case .range(let lower, let upper, let closed):
            return .int(try rangeCount(from: lower, to: upper, closed: closed))
        case .data(let bytes): return .int(Int64(bytes.count))
        case .sequence:
            throw SwiftalkError.type(
                "a Sequence may be infinite — take .prefix(n) or .Array() it deliberately")
        default:
            throw SwiftalkError.unknownMember("\(receiver.typeName).count")
        }
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
