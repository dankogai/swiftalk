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
}

/// An assignment target: a variable, or a subscript path rooted in one
/// (`a[0] = x`, `m[1][0] = x`, `d["k"] = v`).
indirect enum LValue {
    case variable(String)
    case index(LValue, Expr)
}

/// A type annotation: `: Int` or `: Int?` (the flat optional of §3a —
/// `Int?` permits `nil` in the slot, it is not a wrapper type).
struct TypeAnnotation: Equatable {
    let name: String
    let optional: Bool
}

enum Stmt {
    case declaration(mutable: Bool, name: String, annotation: TypeAnnotation?, initializer: Expr)
    case assignment(target: LValue, expr: Expr)
    case expression(Expr)
    indirect case ifS(condition: Expr, then: [Stmt], else: [Stmt]?)
    case whileS(condition: Expr, body: [Stmt])
    case repeatS(body: [Stmt], condition: Expr)
    case forS(name: String, sequence: Expr, body: [Stmt])
    case breakS
    case continueS
}

private let keywords: Set<String> = [
    "let", "var", "true", "false", "nil", "in",
    "if", "else", "while", "repeat", "for", "break", "continue",
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
        var statements: [Stmt] = []
        skipSeparators()
        while pos < tokens.count, peek != closing.map({ .punct($0) }) {
            statements.append(try parseStatement())
            let atEnd = pos == tokens.count || peek == closing.map({ .punct($0) })
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

    /// `if condition { … } [else if … | else { … }]` — Swift-style.
    private mutating func parseIf() throws -> Stmt {
        pos += 1  // consume "if"
        let condition = try withTrailing(false) { try $0.parseExpr() }
        let then = try parseBlock()
        // `else` may sit on the next line; backtrack if it isn't there.
        let saved = pos
        skipSeparators()
        guard case .identifier("else")? = peek else {
            pos = saved
            return .ifS(condition: condition, then: then, else: nil)
        }
        pos += 1
        if case .identifier("if")? = peek {
            return .ifS(condition: condition, then: then, else: [try parseIf()])
        }
        return .ifS(condition: condition, then: then, else: try parseBlock())
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
        var annotation: TypeAnnotation? = nil
        if case .punct(":")? = peek {
            pos += 1
            guard case .identifier(let typeName)? = advance() else {
                throw SwiftalkError.syntax("expected a type name after ':'")
            }
            var optional = false
            if case .punct("?")? = peek {
                pos += 1
                optional = true
            }
            annotation = TypeAnnotation(name: typeName, optional: optional)
        }
        try expect("=")
        return .declaration(mutable: mutable, name: name, annotation: annotation,
                            initializer: try parseExpr())
    }

    // MARK: expressions (ternary > comparison > additive > multiplicative > unary > postfix)

    private mutating func parseExpr() throws -> Expr {
        let condition = try parseComparison()
        guard case .punct("?")? = peek else { return condition }
        pos += 1
        let thenBranch = try parseExpr()
        try expect(":")
        let elseBranch = try parseExpr()
        return .ternary(condition, thenBranch, elseBranch)
    }

    private mutating func parseComparison() throws -> Expr {
        let lhs = try parseRange()
        guard case .op(let op)? = peek, op != "...", op != "..<" else { return lhs }
        pos += 1
        return .comparison(op, lhs, try parseRange())
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
                // Trailing closure (§2.3): the pinned last argument.
                pos += 1
                let closure = try withTrailing(true) { try $0.parseFunction() }
                expr = Parser.attachTrailing(closure, to: expr)
                if case .punct("{")? = peek { break loop }   // no second bare trailing
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
        case .identifier(let name) where keywords.contains(name):
            throw SwiftalkError.syntax("'\(name)' is not an expression")
        case .identifier(let name) where name.hasPrefix("$") && name.count > 1:
            // $N is sugar for $[N] (Design.md §2.4)
            guard let n = Int64(name.dropFirst()) else {
                throw SwiftalkError.syntax("invalid placeholder '\(name)'")
            }
            return .subscript(.variable("$"), .literal(.int(n)))
        case .identifier(let name):
            return .variable(name)
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
            if Set(parameters).count != parameters.count {
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
