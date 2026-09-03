/// AST: literals, collections, bindings, arithmetic/comparison/ternary,
/// method calls — and `{}` functions with `$` (Design.md §2.4).
indirect enum Expr {
    case literal(Value)
    case variable(String)
    case array([Expr])
    case dictionary([(Expr, Expr)])
    case unaryMinus(Expr)
    case binary(Character, Expr, Expr)          // + - * /
    case comparison(String, Expr, Expr)         // == != < <= > >=
    case ternary(Expr, Expr, Expr)
    case function(parameters: [String], body: [Stmt])
    case call(Expr, args: [(label: String?, expr: Expr)])
    case selfCall(args: [(label: String?, expr: Expr)])   // $(...) — recurse (§2.4)
    case method(Expr, name: String, args: [(label: String?, expr: Expr)], called: Bool)
    case `subscript`(Expr, Expr)                          // a[i], d[k]; $0 ≡ $[0]
    case range(String, Expr, Expr)                        // a...b / a..<b (§: eager [Int] for now)
    case interpolation([Expr])                            // "a\(x)b" — parts concatenate
    case memberLiteral(String)                            // .quoted, .hex — format members (§3d)
    case propagate(Expr)                                  // x? — unwrap or early-return (§3a/§8)
    case forceUnwrap(Expr)                                // x! — unwrap or trap
    case awaitE(Expr)                                     // await t — join a Task (§12)
    case logicalAnd(Expr, Expr)                           // a && b — short-circuit (round 69)
    case logicalOr(Expr, Expr)                            // a || b — short-circuit
    case logicalNot(Expr)                                 // !a — prefix
    case superRef                                         // super — receiver position only (round 56)
    case coalesce(Expr, Expr)                             // a ?? b — default on nil/failure
    case optionalMember(Expr, name: String,               // a?.b / a?.b(args) — nil skips
                        args: [(label: String?, expr: Expr)], called: Bool)
}

/// An assignment target: a variable, or a subscript/property path
/// rooted in one (`a[0] = x`, `m[1][0] = x`, `p.x = 1`, `r.origin.x = 5`).
indirect enum LValue {
    case variable(String)
    case index(LValue, Expr)
    case property(LValue, String)
}

/// A type annotation: `: Int` or `: Int?` (the flat optional of §3a —
/// `Int?` permits `nil` in the slot, it is not a wrapper type).
struct TypeAnnotation: Equatable {
    let name: String
    let optional: Bool
    /// Round 59: `[T]` is Array with one parameter, `[K: V]` is
    /// Dictionary with two — recursive, so `[[Int]]` and `[String:
    /// [Int?]]` compose. Empty = an unparameterized name, as before.
    var parameters: [TypeAnnotation] = []

    /// The source spelling, for error messages: `[Int: String?]?`.
    var display: String {
        let base: String
        switch (name, parameters.count) {
        case ("Array", 1):      base = "[\(parameters[0].display)]"
        case ("Dictionary", 2): base = "[\(parameters[0].display): \(parameters[1].display)]"
        default:                base = name
        }
        return optional ? base + "?" : base
    }
}

/// A `switch`/`if case` pattern (§7).
enum Pattern {
    case wildcard                          // _
    case expr(Expr)                        // equality (and Range contains)
    case enumCase(name: String, bindings: [CaseBinding]?)  // .name / .name(let x, _)
}

enum CaseBinding {
    case bind(String)                      // let x
    case wildcard                          // _
}

/// One clause of an `if let` condition list (round 60): a binding
/// that must land non-nil, or a Bool that must hold — evaluated left
/// to right, short-circuiting, later clauses seeing earlier bindings.
enum IfCondition {
    case binding(mutable: Bool, name: String, expr: Expr)
    case boolean(Expr)
}

enum Stmt {
    case declaration(mutable: Bool, name: String, annotation: TypeAnnotation?, initializer: Expr)
    case assignment(target: LValue, expr: Expr)
    case expression(Expr)
    case returnS(Expr?)
    case yieldS(Expr?)
    indirect case ifS(condition: Expr, then: [Stmt], else: [Stmt]?)
    indirect case ifLetS(conditions: [IfCondition], then: [Stmt], else: [Stmt]?)
    indirect case ifCaseS(pattern: Pattern, subject: Expr, then: [Stmt], else: [Stmt]?)
    case whileS(condition: Expr, body: [Stmt])
    case repeatS(body: [Stmt], condition: Expr)
    case forS(name: String, sequence: Expr, body: [Stmt])
    case breakS
    case continueS
    case enumDecl(name: String, caseOrder: [String],
                  cases: [String: [(label: String?, typeName: String?)]],
                  methods: [String: Expr])
    case structDecl(name: String, propertyOrder: [String],
                    properties: [String: Swiftalk.StructType.Property],
                    methods: [String: Expr], inits: [Expr],
                    computed: [String: ComputedSpec])
    case actorDecl(name: String, propertyOrder: [String],
                   properties: [String: Swiftalk.StructType.Property],
                   methods: [String: Expr], inits: [Expr],
                   computed: [String: ComputedSpec])
    case classDecl(name: String, superName: String?, propertyOrder: [String],
                   properties: [String: Swiftalk.StructType.Property],
                   methods: [String: Expr], inits: [Expr],
                   computed: [String: ComputedSpec])
    case extensionDecl(typeName: String, methods: [String: Expr],
                       computed: [String: ComputedSpec])
    case switchS(subject: Expr,
                 clauses: [(patterns: [Pattern], body: [Stmt])],
                 defaultBody: [Stmt]?)
}

/// A computed property as parsed (round 57): `get` and `set` are
/// `.function` exprs (the setter's one parameter is `newValue` or the
/// `set(v)` custom name); nil `set` means read-only.
typealias ComputedSpec = (annotation: TypeAnnotation?, get: Expr, set: Expr?)

private let keywords: Set<String> = [
    "let", "var", "true", "false", "nil", "in",
    "if", "else", "while", "repeat", "for", "break", "continue", "return", "yield",
    "async", "await",
    "enum", "case", "switch", "default", "struct", "extension",
    // "actor", "class", "super" — SHELVED (round 62): the reference
    // types are off the surface; the machinery stays in-tree, dormant.
    // Three fewer keywords: `let class = 1` is legal, like `guard`.
]

struct Parser {
    private let tokens: [Token]
    private var pos = 0
    /// Trailing closures are disabled while parsing control-flow headers
    /// (`if c { }` must read `{` as the block, as in Swift) and re-enabled
    /// inside any parenthesized/bracketed context.
    private var allowTrailing = true

    init(_ tokens: [Token]) {
        self.tokens = tokens
    }

    private mutating func withTrailing<T>(
        _ allowed: Bool, _ body: (inout Parser) throws -> T
    ) rethrows -> T {
        let saved = allowTrailing
        allowTrailing = allowed
        defer { allowTrailing = saved }
        return try body(&self)
    }

    private var peek: Token? { pos < tokens.count ? tokens[pos] : nil }
    private func peek(at offset: Int) -> Token? {
        pos + offset < tokens.count ? tokens[pos + offset] : nil
    }
    private mutating func advance() -> Token? {
        guard pos < tokens.count else { return nil }
        defer { pos += 1 }
        return tokens[pos]
    }
    private mutating func expect(_ p: Character) throws {
        guard advance() == .punct(p) else {
            throw SwiftalkError.syntax("expected '\(p)'")
        }
    }

    // MARK: statements

    /// Parses a whole program: statements separated by newlines or `;`.
    mutating func parseProgram() throws -> [Stmt] {
        let statements = try parseStatements(until: nil)
        guard !statements.isEmpty else {
            throw SwiftalkError.syntax("empty program")
        }
        return statements
    }

    /// Parses statements until `closing` (or end of input when nil).
    /// Does not consume the closing token.
    private mutating func parseStatements(until closing: Character?) throws -> [Stmt] {
        try parseStatements(stopWhen: { $0 == closing.map { .punct($0) } })
    }

    private mutating func parseStatements(stopWhen stop: (Token?) -> Bool) throws -> [Stmt] {
        var statements: [Stmt] = []
        skipSeparators()
        while pos < tokens.count, !stop(peek) {
            statements.append(try parseStatement())
            let atEnd = pos == tokens.count || stop(peek)
            guard atEnd || consumeSeparator() else {
                throw SwiftalkError.syntax("expected a newline or ';' between statements")
            }
            skipSeparators()
        }
        return statements
    }

    private mutating func consumeSeparator() -> Bool {
        switch peek {
        case .newline, .punct(";"):
            pos += 1
            return true
        default:
            return false
        }
    }
    private mutating func skipSeparators() {
        while consumeSeparator() {}
    }

    private mutating func parseStatement() throws -> Stmt {
        switch peek {
        case .identifier("let"), .identifier("var"):
            return try parseDeclaration()
        case .identifier("if"):
            return try parseIf()
        case .identifier("while"):
            pos += 1
            let condition = try withTrailing(false) { try $0.parseExpr() }
            return .whileS(condition: condition, body: try parseBlock())
        case .identifier("repeat"):
            pos += 1
            let body = try parseBlock()
            guard case .identifier("while")? = advance() else {
                throw SwiftalkError.syntax("expected 'while' after the repeat block")
            }
            return .repeatS(body: body, condition: try withTrailing(false) { try $0.parseExpr() })
        case .identifier("for"):
            pos += 1
            guard case .identifier(let name)? = advance(),
                  name == "_" || (!keywords.contains(name) && !name.hasPrefix("$")) else {
                throw SwiftalkError.syntax("expected a loop variable after 'for'")
            }
            guard case .identifier("in")? = advance() else {
                throw SwiftalkError.syntax("expected 'in' after the loop variable")
            }
            let sequence = try withTrailing(false) { try $0.parseExpr() }
            return .forS(name: name, sequence: sequence, body: try parseBlock())
        case .identifier("enum"):
            return try parseEnum()
        case .identifier("struct"):
            return try parseStruct(kind: "struct")
        // SHELVED (round 62): `actor` (round 54) and `class` (rounds
        // 55–56) are off the surface for now — the routes below stay
        // for their possible return:
        // case .identifier("actor"): return try parseStruct(kind: "actor")
        // case .identifier("class"): return try parseStruct(kind: "class")
        case .identifier("extension"):
            return try parseExtension()
        case .identifier("switch"):
            return try parseSwitch()
        case .identifier("return"):
            pos += 1
            switch peek {
            case nil, .newline, .punct(";"), .punct("}"):
                return .returnS(nil)
            default:
                return .returnS(try parseExpr())
            }
        case .identifier("yield"):
            pos += 1
            switch peek {
            case nil, .newline, .punct(";"), .punct("}"):
                return .yieldS(nil)
            default:
                return .yieldS(try parseExpr())
            }
        case .identifier("break"):
            pos += 1
            return .breakS
        case .identifier("continue"):
            pos += 1
            return .continueS
        default:
            let expr = try parseExpr()
            guard case .punct("=")? = peek else {
                return .expression(expr)
            }
            pos += 1
            return .assignment(target: try lvalue(from: expr), expr: try parseExpr())
        }
    }

    /// Parses one `\(...)` interpolation body: a single expression,
    /// nothing trailing.
    mutating func parseInterpolatedExpr() throws -> Expr {
        let expr = try parseExpr()
        guard pos == tokens.count else {
            throw SwiftalkError.syntax("'\\(...)' takes a single expression")
        }
        return expr
    }

    /// `if condition { … }` or `if case pattern = expr { … }`, with
    /// `else`/`else if` — Swift-style.
    private mutating func parseIf() throws -> Stmt {
        pos += 1  // consume "if"
        if case .identifier("case")? = peek {
            pos += 1
            let pattern = try parsePattern()
            try expect("=")
            let subject = try withTrailing(false) { try $0.parseExpr() }
            let then = try parseBlock()
            let elseBranch = try parseElse()
            return .ifCaseS(pattern: pattern, subject: subject, then: then, else: elseBranch)
        }
        // A comma-separated condition list (round 60): booleans and
        // `let`/`var` bindings mix — `if x > 0, let y = f(x), y < 9`.
        // (`guard` is deliberately absent: it is only `if not` — §9.)
        var conditions: [IfCondition] = []
        while true {
            if peek == .identifier("let") || peek == .identifier("var") {
                let mutable = peek == .identifier("var")
                pos += 1
                guard case .identifier(let name)? = advance(),
                      !keywords.contains(name), !name.hasPrefix("$") else {
                    throw SwiftalkError.syntax("expected a name after 'if let'")
                }
                let expr: Expr
                if case .punct("=")? = peek {
                    pos += 1
                    expr = try withTrailing(false) { try $0.parseExpr() }
                } else {
                    expr = .variable(name)     // shorthand: if let x { }
                }
                conditions.append(.binding(mutable: mutable, name: name, expr: expr))
            } else {
                conditions.append(.boolean(try withTrailing(false) { try $0.parseExpr() }))
            }
            guard case .punct(",")? = peek else { break }
            pos += 1
        }
        let then = try parseBlock()
        let elseBranch = try parseElse()
        if conditions.count == 1, case .boolean(let condition) = conditions[0] {
            return .ifS(condition: condition, then: then, else: elseBranch)
        }
        return .ifLetS(conditions: conditions, then: then, else: elseBranch)
    }

    /// The optional `else`/`else if` tail; `else` may sit on the next
    /// line (backtracks when absent).
    private mutating func parseElse() throws -> [Stmt]? {
        let saved = pos
        skipSeparators()
        guard case .identifier("else")? = peek else {
            pos = saved
            return nil
        }
        pos += 1
        if case .identifier("if")? = peek {
            return [try parseIf()]
        }
        return try parseBlock()
    }

    /// `enum Name { case a, b(label: Type, Type), ... }` (§7, round 45).
    private mutating func parseEnum() throws -> Stmt {
        pos += 1  // consume "enum"
        guard case .identifier(let name)? = advance(),
              !keywords.contains(name), !name.hasPrefix("$") else {
            throw SwiftalkError.syntax("expected a name after 'enum'")
        }
        try expect("{")
        var caseOrder: [String] = []
        var cases: [String: [(label: String?, typeName: String?)]] = [:]
        var methods: [String: Expr] = [:]
        skipSeparators()
        while peek != .punct("}") {
            // Methods (round 48): `let name = { ... }` among the cases.
            if case .identifier("let")? = peek {
                let (methodName, fn) = try parseMethod(existing: { cases[$0] != nil || methods[$0] != nil })
                methods[methodName] = fn
                guard peek == .punct("}") || consumeSeparator() else {
                    throw SwiftalkError.syntax("expected a newline between enum members")
                }
                skipSeparators()
                continue
            }
            guard case .identifier("case")? = advance() else {
                throw SwiftalkError.syntax("expected 'case' or a 'let' method in an enum body")
            }
            repeat {
                guard case .identifier(let caseName)? = advance(),
                      !keywords.contains(caseName) else {
                    throw SwiftalkError.syntax("expected a case name")
                }
                guard cases[caseName] == nil else {
                    throw SwiftalkError.syntax("duplicate case '\(caseName)'")
                }
                var params: [(label: String?, typeName: String?)] = []
                if case .punct("(")? = peek {
                    pos += 1
                    repeat {
                        guard case .identifier(let first)? = advance() else {
                            throw SwiftalkError.syntax("expected an associated-value type")
                        }
                        if case .punct(":")? = peek {
                            pos += 1
                            guard case .identifier(let typeName)? = advance() else {
                                throw SwiftalkError.syntax("expected a type after ':'")
                            }
                            params.append((first, typeName))
                        } else {
                            params.append((nil, first))
                        }
                    } while consumeComma(closing: ")")
                    try expect(")")
                }
                caseOrder.append(caseName)
                cases[caseName] = params
            } while consumeComma(closing: "}")
            guard peek == .punct("}") || consumeSeparator() else {
                throw SwiftalkError.syntax("expected a newline between enum cases")
            }
            skipSeparators()
        }
        try expect("}")
        return .enumDecl(name: name, caseOrder: caseOrder, cases: cases, methods: methods)
    }

    /// `let name = { ... }` inside a type body — a method (round 48):
    /// the uniform no-`func` spelling; `self` binds at invocation.
    private mutating func parseMethod(existing: (String) -> Bool) throws -> (String, Expr) {
        pos += 1  // consume "let"
        guard case .identifier(let methodName)? = advance(),
              !keywords.contains(methodName), !methodName.hasPrefix("$") else {
            throw SwiftalkError.syntax("expected a method name after 'let'")
        }
        guard !existing(methodName) else {
            throw SwiftalkError.syntax("duplicate member '\(methodName)'")
        }
        try expect("=")
        let fn = try parseExpr()
        guard case .function = fn else {
            throw SwiftalkError.syntax(
                "a type-body 'let' holds a method: let \(methodName) = { ... }")
        }
        return (methodName, fn)
    }

    /// `struct Name { var x: Int = 0\nlet y = 1\nvar z: Double }`
    /// (§4, round 46): stored properties — mutability, optional
    /// annotation, optional default; at least one of the two required.
    private mutating func parseStruct(kind: String) throws -> Stmt {
        pos += 1  // consume "struct"/"actor"
        guard case .identifier(let name)? = advance(),
              !keywords.contains(name), !name.hasPrefix("$") else {
            throw SwiftalkError.syntax("expected a name after '\(kind)'")
        }
        var superName: String? = nil
        if kind == "class", case .punct(":")? = peek {
            pos += 1
            guard case .identifier(let sup)? = advance(),
                  !keywords.contains(sup), !sup.hasPrefix("$") else {
                throw SwiftalkError.syntax("expected a superclass name after ':'")
            }
            superName = sup
        }
        try expect("{")
        var propertyOrder: [String] = []
        var properties: [String: Swiftalk.StructType.Property] = [:]
        var methods: [String: Expr] = [:]
        var inits: [Expr] = []
        var computed: [String: ComputedSpec] = [:]
        skipSeparators()
        while peek != .punct("}") {
            // Initializers (round 48): `init { params in ... }`.
            if case .identifier("init")? = peek {
                pos += 1
                guard case .punct("{")? = advance() else {
                    throw SwiftalkError.syntax("expected '{' after 'init'")
                }
                inits.append(try withTrailing(true) { try $0.parseFunction() })
                guard peek == .punct("}") || consumeSeparator() else {
                    throw SwiftalkError.syntax("expected a newline between \(kind) members")
                }
                skipSeparators()
                continue
            }
            guard case .identifier(let keyword)? = advance(),
                  keyword == "var" || keyword == "let" else {
                throw SwiftalkError.syntax(
                    "a \(kind) body holds 'var'/'let' properties, methods, and inits")
            }
            guard case .identifier(let propName)? = advance(),
                  !keywords.contains(propName), !propName.hasPrefix("$") else {
                throw SwiftalkError.syntax("expected a property name")
            }
            guard properties[propName] == nil, methods[propName] == nil,
                  computed[propName] == nil else {
                throw SwiftalkError.syntax("duplicate member '\(propName)'")
            }
            var annotation: TypeAnnotation? = nil
            if case .punct(":")? = peek {
                pos += 1
                annotation = try parseTypeAnnotation()
            }
            // A brace where `=` would go: an OBSERVER block on an
            // annotated stored property (round 58b), or a COMPUTED
            // property (round 57) — willSet/didSet disambiguates.
            if case .punct("{")? = peek {
                guard keyword == "var" else {
                    throw SwiftalkError.syntax(
                        "a computed property is declared 'var' — it computes, it is not constant storage")
                }
                if isObserverBlock(at: pos + 1) {
                    guard annotation != nil else {
                        throw SwiftalkError.syntax(
                            "an observed property needs a type annotation or a default value")
                    }
                    pos += 1
                    let (will, did) = try parseObserverBlock()
                    propertyOrder.append(propName)
                    properties[propName] = Swiftalk.StructType.Property(
                        mutable: true, annotation: annotation, defaultExpr: nil,
                        willSetExpr: will, didSetExpr: did)
                } else {
                    pos += 1
                    let (getter, setter) = try parseComputedBody()
                    computed[propName] = (annotation: annotation, get: getter, set: setter)
                }
                guard peek == .punct("}") || consumeSeparator() else {
                    throw SwiftalkError.syntax("expected a newline between \(kind) members")
                }
                skipSeparators()
                continue
            }
            var defaultExpr: Expr? = nil
            if case .punct("=")? = peek {
                pos += 1
                defaultExpr = try parseExpr()
            }
            // `var x = 0 { willSet { ... } }` — observers after the
            // default (round 58b; the trailing-closure grab refuses
            // observer blocks, so the brace is still here).
            var observerPair: (will: Expr?, did: Expr?)? = nil
            if case .punct("{")? = peek, isObserverBlock(at: pos + 1) {
                guard keyword == "var" else {
                    throw SwiftalkError.syntax("only a 'var' property is observable")
                }
                pos += 1
                observerPair = try parseObserverBlock()
            }
            // A `let` bound to a closure literal is a METHOD (round 48) —
            // store a Function in a `var` if you truly want a stored one.
            if keyword == "let", annotation == nil, let fn = defaultExpr,
               case .function = fn {
                methods[propName] = fn
            } else {
                guard annotation != nil || defaultExpr != nil else {
                    throw SwiftalkError.syntax(
                        "property '\(propName)' needs a type annotation or a default value")
                }
                propertyOrder.append(propName)
                properties[propName] = Swiftalk.StructType.Property(
                    mutable: keyword == "var", annotation: annotation, defaultExpr: defaultExpr,
                    willSetExpr: observerPair?.will, didSetExpr: observerPair?.did)
            }
            guard peek == .punct("}") || consumeSeparator() else {
                throw SwiftalkError.syntax("expected a newline between properties")
            }
            skipSeparators()
        }
        try expect("}")
        switch kind {
        case "actor":
            return .actorDecl(name: name, propertyOrder: propertyOrder, properties: properties,
                              methods: methods, inits: inits, computed: computed)
        case "class":
            return .classDecl(name: name, superName: superName, propertyOrder: propertyOrder,
                              properties: properties, methods: methods, inits: inits,
                              computed: computed)
        default:
            return .structDecl(name: name, propertyOrder: propertyOrder, properties: properties,
                               methods: methods, inits: inits, computed: computed)
        }
    }

    /// A type annotation, recursive (round 59): a name, `[Element]`,
    /// or `[Key: Value]` — each optionally suffixed `?`.
    private mutating func parseTypeAnnotation() throws -> TypeAnnotation {
        if case .punct("[")? = peek {
            pos += 1
            var parameters = [try parseTypeAnnotation()]
            var name = "Array"
            if case .punct(":")? = peek {
                pos += 1
                parameters.append(try parseTypeAnnotation())
                name = "Dictionary"
            }
            try expect("]")
            var optional = false
            if peek == .punct("?") || peek == .op("?") {
                pos += 1
                optional = true
            }
            return TypeAnnotation(name: name, optional: optional, parameters: parameters)
        }
        guard case .identifier(let typeName)? = advance(), !keywords.contains(typeName) else {
            throw SwiftalkError.syntax("expected a type name after ':'")
        }
        var optional = false
        if peek == .punct("?") || peek == .op("?") {
            pos += 1
            optional = true
        }
        return TypeAnnotation(name: typeName, optional: optional)
    }

    /// Does a `{` at `index` open a willSet/didSet observer block?
    /// (Peeks past newlines for an observer keyword followed by its
    /// block or parameter — the disambiguator against both trailing
    /// closures and computed properties.)
    private func isObserverBlock(at index: Int) -> Bool {
        var i = index
        while case .newline? = (i < tokens.count ? tokens[i] : nil) { i += 1 }
        guard i + 1 < tokens.count,
              case .identifier(let word) = tokens[i],
              word == "willSet" || word == "didSet" else { return false }
        return tokens[i + 1] == .punct("{") || tokens[i + 1] == .punct("(")
    }

    /// `{ willSet[(v)] { ... } didSet[(v)] { ... } }`, `{` already
    /// consumed — either order, each at most once, at least one
    /// (round 58b). Parameters default to newValue / oldValue.
    private mutating func parseObserverBlock() throws -> (will: Expr?, did: Expr?) {
        var will: Expr? = nil
        var did: Expr? = nil
        skipSeparators()
        while case .identifier(let word)? = peek, word == "willSet" || word == "didSet" {
            pos += 1
            var param = word == "willSet" ? "newValue" : "oldValue"
            if case .punct("(")? = peek {
                pos += 1
                guard case .identifier(let custom)? = advance(),
                      !keywords.contains(custom), !custom.hasPrefix("$") else {
                    throw SwiftalkError.syntax("expected a parameter name in \(word)(...)")
                }
                param = custom
                try expect(")")
            }
            try expect("{")
            let body = try parseStatements(until: "}")
            try expect("}")
            let fn = Expr.function(parameters: [param], body: body)
            if word == "willSet" {
                guard will == nil else { throw SwiftalkError.syntax("duplicate 'willSet'") }
                will = fn
            } else {
                guard did == nil else { throw SwiftalkError.syntax("duplicate 'didSet'") }
                did = fn
            }
            skipSeparators()
        }
        guard will != nil || did != nil else {
            throw SwiftalkError.syntax("an observer block holds willSet and/or didSet")
        }
        try expect("}")
        return (will, did)
    }

    /// The body of a computed property, `{` already consumed: either
    /// `get { ... }` / `set[(v)] { ... }` blocks (get required), or a
    /// bare block that IS the getter (round 57).
    private mutating func parseComputedBody() throws -> (get: Expr, set: Expr?) {
        skipSeparators()
        guard peek == .identifier("get") || peek == .identifier("set") else {
            let body = try parseStatements(until: "}")
            try expect("}")
            return (.function(parameters: [], body: body), nil)
        }
        var getBody: [Stmt]? = nil
        var setExpr: Expr? = nil
        while peek == .identifier("get") || peek == .identifier("set") {
            if case .identifier("get")? = peek {
                guard getBody == nil else {
                    throw SwiftalkError.syntax("duplicate 'get'")
                }
                pos += 1
                try expect("{")
                getBody = try parseStatements(until: "}")
                try expect("}")
            } else {
                guard setExpr == nil else {
                    throw SwiftalkError.syntax("duplicate 'set'")
                }
                pos += 1
                var param = "newValue"
                if case .punct("(")? = peek {
                    pos += 1
                    guard case .identifier(let custom)? = advance(),
                          !keywords.contains(custom), !custom.hasPrefix("$") else {
                        throw SwiftalkError.syntax("expected a parameter name in set(...)")
                    }
                    param = custom
                    try expect(")")
                }
                try expect("{")
                let body = try parseStatements(until: "}")
                try expect("}")
                setExpr = .function(parameters: [param], body: body)
            }
            skipSeparators()
        }
        guard let getBody else {
            throw SwiftalkError.syntax("a computed property needs a 'get'")
        }
        try expect("}")
        return (.function(parameters: [], body: getBody), setExpr)
    }

    /// `extension Name { let m = { ... } }` (§10, rounds 49–50):
    /// methods added to an existing type — user or builtin.
    private mutating func parseExtension() throws -> Stmt {
        pos += 1  // consume "extension"
        guard case .identifier(let typeName)? = advance(),
              !keywords.contains(typeName), !typeName.hasPrefix("$") else {
            throw SwiftalkError.syntax("expected a type name after 'extension'")
        }
        try expect("{")
        var methods: [String: Expr] = [:]
        var computed: [String: ComputedSpec] = [:]
        skipSeparators()
        while peek != .punct("}") {
            // `var name [: Type] { ... }` — a computed property
            // (round 57); `let name = { ... }` — a method.
            if case .identifier("var")? = peek {
                pos += 1
                guard case .identifier(let propName)? = advance(),
                      !keywords.contains(propName), !propName.hasPrefix("$") else {
                    throw SwiftalkError.syntax("expected a property name after 'var'")
                }
                guard methods[propName] == nil, computed[propName] == nil else {
                    throw SwiftalkError.syntax("duplicate member '\(propName)'")
                }
                var annotation: TypeAnnotation? = nil
                if case .punct(":")? = peek {
                    pos += 1
                    annotation = try parseTypeAnnotation()
                }
                try expect("{")
                let (getter, setter) = try parseComputedBody()
                computed[propName] = (annotation: annotation, get: getter, set: setter)
            } else {
                guard case .identifier("let")? = peek else {
                    throw SwiftalkError.syntax(
                        "an extension body holds 'let' methods and 'var' computed properties")
                }
                let (methodName, fn) = try parseMethod(existing: {
                    methods[$0] != nil || computed[$0] != nil
                })
                methods[methodName] = fn
            }
            guard peek == .punct("}") || consumeSeparator() else {
                throw SwiftalkError.syntax("expected a newline between extension members")
            }
            skipSeparators()
        }
        try expect("}")
        return .extensionDecl(typeName: typeName, methods: methods, computed: computed)
    }

    /// `switch expr { case pattern, ...: stmts ... default: stmts }` (§7).
    private mutating func parseSwitch() throws -> Stmt {
        pos += 1  // consume "switch"
        let subject = try withTrailing(false) { try $0.parseExpr() }
        try expect("{")
        var clauses: [(patterns: [Pattern], body: [Stmt])] = []
        var defaultBody: [Stmt]? = nil
        skipSeparators()
        while peek != .punct("}") {
            switch advance() {
            case .identifier("case"):
                var patterns = [try parsePattern()]
                while case .punct(",")? = peek {
                    pos += 1
                    patterns.append(try parsePattern())
                }
                try expect(":")
                clauses.append((patterns, try parseCaseBody()))
            case .identifier("default"):
                guard defaultBody == nil else {
                    throw SwiftalkError.syntax("duplicate 'default'")
                }
                try expect(":")
                defaultBody = try parseCaseBody()
            default:
                throw SwiftalkError.syntax("expected 'case' or 'default' in a switch body")
            }
        }
        try expect("}")
        return .switchS(subject: subject, clauses: clauses, defaultBody: defaultBody)
    }

    private mutating func parseCaseBody() throws -> [Stmt] {
        try parseStatements(stopWhen: { token in
            switch token {
            case .identifier("case"), .identifier("default"), .punct("}"):
                return true
            default:
                return false
            }
        })
    }

    /// A pattern: `_`, `.name`, `.name(let x, _)`, or an expression
    /// (equality; a Range expression matches by containment). Parsed at
    /// comparison level — ternary would fight the clause's `:`.
    private mutating func parsePattern() throws -> Pattern {
        switch peek {
        case .identifier("_"):
            pos += 1
            return .wildcard
        case .punct("."):
            pos += 1
            guard case .identifier(let name)? = advance(), !keywords.contains(name) else {
                throw SwiftalkError.syntax("expected a case name after '.'")
            }
            guard case .punct("(")? = peek else {
                return .enumCase(name: name, bindings: nil)
            }
            pos += 1
            var bindings: [CaseBinding] = []
            if peek != .punct(")") {
                repeat {
                    switch advance() {
                    case .identifier("let"):
                        guard case .identifier(let binding)? = advance(),
                              !keywords.contains(binding), !binding.hasPrefix("$") else {
                            throw SwiftalkError.syntax("expected a name after 'let'")
                        }
                        bindings.append(.bind(binding))
                    case .identifier("_"):
                        bindings.append(.wildcard)
                    default:
                        throw SwiftalkError.syntax(
                            "a case pattern binds with 'let x' or ignores with '_'")
                    }
                } while consumeComma(closing: ")")
            }
            try expect(")")
            return .enumCase(name: name, bindings: bindings)
        default:
            return .expr(try parseComparison())
        }
    }

    /// `{ statements }` in statement context — a block, not a closure.
    private mutating func parseBlock() throws -> [Stmt] {
        try expect("{")
        let body = try parseStatements(until: "}")
        try expect("}")
        return body
    }

    /// Converts an already-parsed expression into an assignment target:
    /// a variable, or subscripts rooted in one.
    private func lvalue(from expr: Expr) throws -> LValue {
        switch expr {
        case .variable(let name):
            return .variable(name)
        case .subscript(let base, let index):
            return .index(try lvalue(from: base), index)
        case .method(let base, let name, let args, false) where args.isEmpty:
            return .property(try lvalue(from: base), name)
        case .memberLiteral(let name):
            // Implicit self (round 49): `.x = 1` in a type body.
            return .property(.variable("self"), name)
        default:
            throw SwiftalkError.syntax("this expression is not assignable")
        }
    }

    private mutating func parseDeclaration() throws -> Stmt {
        guard case .identifier(let keyword)? = advance() else { fatalError("unreachable") }
        let mutable = keyword == "var"
        guard case .identifier(let name)? = advance() else {
            throw SwiftalkError.syntax("expected a name after '\(keyword)'")
        }
        if keywords.contains(name) || name.hasPrefix("$") {
            throw SwiftalkError.syntax("'\(name)' cannot be declared")
        }
        // (Round 61 reverted round 58a's `let name(x:y:) { body }`
        // sugar — swiftalk was getting too close to Swift. `{ x, y in
        // body }` is once again the one and only spelling.)
        var annotation: TypeAnnotation? = nil
        if case .punct(":")? = peek {
            pos += 1
            annotation = try parseTypeAnnotation()
        }
        try expect("=")
        return .declaration(mutable: mutable, name: name, annotation: annotation,
                            initializer: try parseExpr())
    }

    // MARK: expressions (ternary > comparison > additive > multiplicative > unary > postfix)

    private mutating func parseExpr() throws -> Expr {
        let condition = try parseDisjunction()
        guard case .punct("?")? = peek else { return condition }
        pos += 1
        let thenBranch = try parseExpr()
        try expect(":")
        let elseBranch = try parseExpr()
        return .ternary(condition, thenBranch, elseBranch)
    }

    /// `a || b` — left-associative, short-circuit; binds looser than
    /// `&&`, tighter than the ternary (Swift's precedence, round 69).
    private mutating func parseDisjunction() throws -> Expr {
        var lhs = try parseConjunction()
        while case .op("||")? = peek {
            pos += 1
            lhs = .logicalOr(lhs, try parseConjunction())
        }
        return lhs
    }

    /// `a && b` — left-associative, short-circuit; binds tighter than
    /// `||`, looser than comparison.
    private mutating func parseConjunction() throws -> Expr {
        var lhs = try parseComparison()
        while case .op("&&")? = peek {
            pos += 1
            lhs = .logicalAnd(lhs, try parseComparison())
        }
        return lhs
    }

    private mutating func parseComparison() throws -> Expr {
        let lhs = try parseCoalescing()
        guard case .op(let op)? = peek,
              !["...", "..<", "??", "?", "!", "?.", "&&", "||"].contains(op) else { return lhs }
        pos += 1
        return .comparison(op, lhs, try parseCoalescing())
    }

    /// `a ?? b` — right-associative, lazy on the right (round 51).
    private mutating func parseCoalescing() throws -> Expr {
        let lhs = try parseRange()
        guard case .op("??")? = peek else { return lhs }
        pos += 1
        return .coalesce(lhs, try parseCoalescing())
    }

    private mutating func parseRange() throws -> Expr {
        let lhs = try parseAdditive()
        guard case .op(let op)? = peek, op == "..." || op == "..<" else { return lhs }
        pos += 1
        return .range(op, lhs, try parseAdditive())
    }

    private mutating func parseAdditive() throws -> Expr {
        var lhs = try parseMultiplicative()
        while case .punct(let op)? = peek, op == "+" || op == "-" {
            pos += 1
            lhs = .binary(op, lhs, try parseMultiplicative())
        }
        return lhs
    }

    private mutating func parseMultiplicative() throws -> Expr {
        var lhs = try parseUnary()
        while case .punct(let op)? = peek, op == "*" || op == "/" {
            pos += 1
            lhs = .binary(op, lhs, try parseUnary())
        }
        return lhs
    }

    private mutating func parseUnary() throws -> Expr {
        if case .punct("-")? = peek {
            pos += 1
            return .unaryMinus(try parseUnary())
        }
        if case .op("!")? = peek {
            // Prefix `!` — logical not (round 69). Postfix `!` (force
            // unwrap) lives in parsePostfix; position tells them apart.
            pos += 1
            return .logicalNot(try parseUnary())
        }
        if case .identifier("await")? = peek {
            // Prefix, binding at unary level — the JS way, so
            // `await t1 + await t2` reads as `(await t1) + (await t2)`.
            pos += 1
            return .awaitE(try parseUnary())
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> Expr {
        var expr = try parsePrimary()
        loop: while true {
            switch peek {
            case .punct("."):
                pos += 1
                guard case .identifier(let name)? = advance() else {
                    throw SwiftalkError.syntax("expected member name after '.'")
                }
                var args: [(label: String?, expr: Expr)] = []
                var called = false
                if case .punct("(")? = peek {
                    called = true
                    args = try parseCallArguments()
                }
                expr = .method(expr, name: name, args: args, called: called)
            case .punct("("):
                let args = try parseCallArguments()
                if case .variable("$") = expr {
                    expr = .selfCall(args: args)      // $(...) recurses (§2.4)
                } else {
                    expr = .call(expr, args: args)
                }
            case .punct("["):
                pos += 1
                let index = try withTrailing(true) { try $0.parseExpr() }
                try expect("]")
                expr = .subscript(expr, index)
            case .punct("{") where allowTrailing:
                // An observer block (round 58b) is NOT a trailing
                // closure — `var x = 0 { willSet { ... } }` must leave
                // the brace for the property parser.
                if isObserverBlock(at: pos + 1) { break loop }
                // Trailing closure (§2.3): the pinned last argument.
                pos += 1
                let closure = try withTrailing(true) { try $0.parseFunction() }
                expr = Parser.attachTrailing(closure, to: expr)
                if case .punct("{")? = peek { break loop }   // no second bare trailing
            case .op("?"):
                pos += 1
                expr = .propagate(expr)
            case .op("!"):
                pos += 1
                expr = .forceUnwrap(expr)
            case .op("?."):
                pos += 1
                guard case .identifier(let name)? = advance(), !keywords.contains(name) else {
                    throw SwiftalkError.syntax("expected a member name after '?.'")
                }
                var args: [(label: String?, expr: Expr)] = []
                var called = false
                if case .punct("(")? = peek {
                    called = true
                    args = try parseCallArguments()
                }
                expr = .optionalMember(expr, name: name, args: args, called: called)
            default:
                break loop
            }
        }
        return expr
    }

    /// Attaches a trailing closure as the last argument of whatever call
    /// shape precedes it — `f { }`, `f(a) { }`, `a.map { }`, `$(n) { }`.
    private static func attachTrailing(_ closure: Expr, to expr: Expr) -> Expr {
        switch expr {
        case .method(let receiver, let name, var args, _):
            args.append((nil, closure))
            return .method(receiver, name: name, args: args, called: true)
        case .call(let callee, var args):
            args.append((nil, closure))
            return .call(callee, args: args)
        case .selfCall(var args):
            args.append((nil, closure))
            return .selfCall(args: args)
        default:
            return .call(expr, args: [(nil, closure)])
        }
    }

    /// Parses `( [label:] expr, ... )` — labels are optional and, per
    /// §2.3, matched by name (reorderable) at call time.
    private mutating func parseCallArguments() throws -> [(label: String?, expr: Expr)] {
        try expect("(")
        var args: [(label: String?, expr: Expr)] = []
        try withTrailing(true) {
            if $0.peek != .punct(")") {
                repeat {
                    if case .identifier(let label)? = $0.peek, $0.peek(at: 1) == .punct(":"),
                       !keywords.contains(label) {
                        guard label != "_" else {
                            // round 61: `_` parameters have no label —
                            // pass the value positionally
                            throw SwiftalkError.syntax("'_' is not an argument label")
                        }
                        $0.pos += 2
                        args.append((label, try $0.parseExpr()))
                    } else {
                        args.append((nil, try $0.parseExpr()))
                    }
                } while $0.consumeComma(closing: ")")
            }
        }
        try expect(")")
        return args
    }

    /// Consumes a `,` and reports whether more elements follow — a comma
    /// directly before the closing bracket is a trailing comma (allowed,
    /// as in Swift 6.1+).
    private mutating func consumeComma(closing: Character) -> Bool {
        guard case .punct(",")? = peek else { return false }
        pos += 1
        return peek != .punct(closing)
    }

    private mutating func parsePrimary() throws -> Expr {
        switch advance() {
        case .int(let i):     return .literal(.int(i))
        case .double(let d):  return .literal(.double(d))
        case .string(let s):  return .literal(.string(s))
        case .interpolated(let segments):
            return .interpolation(try segments.map { segment in
                switch segment {
                case .literal(let s):
                    return .literal(.string(s))
                case .interpolation(let tokens):
                    var sub = Parser(tokens)
                    return try sub.parseInterpolatedExpr()
                }
            })
        case .identifier("true"):  return .literal(.bool(true))
        case .identifier("false"): return .literal(.bool(false))
        case .identifier("nil"):   return .literal(.nil)
        // SHELVED (round 62) with class: `super` (round 56) —
        // case .identifier("super"): return .superRef
        case .identifier("async"):
            // `async { ... }` is sugar for `Task { ... }` (round 53):
            // the word survives at the spawn site, not as a function
            // color — swiftalk functions are colorless.
            guard case .punct("{")? = advance() else {
                throw SwiftalkError.syntax("expected '{' after 'async' — async { ... } spawns a Task")
            }
            let closure = try withTrailing(true) { try $0.parseFunction() }
            return .call(.variable("Task"), args: [(nil, closure)])
        case .identifier(let name) where keywords.contains(name):
            throw SwiftalkError.syntax("'\(name)' is not an expression")
        case .identifier(let name) where name.hasPrefix("$") && name.count > 1:
            // $N binds the N-th argument at entry (round 41 refines round
            // 32: $N == $[N] until `$` is reassigned — generators reassign
            // `$` to advance their state while $N stay entry snapshots).
            guard Int64(name.dropFirst()) != nil else {
                throw SwiftalkError.syntax("invalid placeholder '\(name)'")
            }
            return .variable(name)
        case .identifier(let name):
            return .variable(name)
        case .punct("."):
            // Implicit member (§3d format arguments): .quoted, .hex, ...
            guard case .identifier(let name)? = advance(), !keywords.contains(name) else {
                throw SwiftalkError.syntax("expected a member name after '.'")
            }
            return .memberLiteral(name)
        case .punct("("):
            let inner = try withTrailing(true) { try $0.parseExpr() }
            try expect(")")
            return inner
        case .punct("["):
            return try withTrailing(true) { try $0.parseCollection() }
        case .punct("{"):
            return try withTrailing(true) { try $0.parseFunction() }
        case let t:
            throw SwiftalkError.syntax("unexpected token \(t.map { "\($0)" } ?? "end of input")")
        }
    }

    /// Parses the remainder of a `{...}` function literal (§2.4): an
    /// optional `x, y in` parameter list, then a statement-list body.
    private mutating func parseFunction() throws -> Expr {
        let parameters = try parseParameterList()
        let body = try parseStatements(until: "}")
        try expect("}")
        return .function(parameters: parameters, body: body)
    }

    /// Recognizes `ident (, ident)* in` — backtracks when the braces turn
    /// out to open a parameter-less body instead.
    private mutating func parseParameterList() throws -> [String] {
        let saved = pos
        skipSeparators()
        var parameters: [String] = []
        while case .identifier(let name)? = peek,
              !keywords.contains(name), !name.hasPrefix("$") {
            parameters.append(name)
            pos += 1
            if case .punct(",")? = peek {
                pos += 1
                continue
            }
            break
        }
        if !parameters.isEmpty, case .identifier("in")? = peek {
            pos += 1
            // `_` is a positional-only parameter (round 61): no label,
            // no binding — the value reaches the body as $N alone. It
            // may repeat; named parameters may not.
            let named = parameters.filter { $0 != "_" }
            if Set(named).count != named.count {
                throw SwiftalkError.syntax("duplicate parameter name")
            }
            return parameters
        }
        pos = saved
        return []
    }

    /// Parses the remainder of a `[...]` literal: array, dictionary, or the
    /// empty forms `[]` / `[:]`.
    private mutating func parseCollection() throws -> Expr {
        if case .punct("]")? = peek {          // []
            pos += 1
            return .array([])
        }
        if case .punct(":")? = peek {          // [:]
            pos += 1
            try expect("]")
            return .dictionary([])
        }
        let first = try parseExpr()
        if case .punct(":")? = peek {          // dictionary
            pos += 1
            var pairs: [(Expr, Expr)] = [(first, try parseExpr())]
            while consumeComma(closing: "]") {
                let key = try parseExpr()
                try expect(":")
                pairs.append((key, try parseExpr()))
            }
            try expect("]")
            return .dictionary(pairs)
        }
        var elements = [first]                 // array
        while consumeComma(closing: "]") {
            elements.append(try parseExpr())
        }
        try expect("]")
        return .array(elements)
    }
}
