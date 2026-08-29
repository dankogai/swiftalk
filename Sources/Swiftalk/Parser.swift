/// Milestone-0 AST: literal expressions, collections, unary minus,
/// same-type arithmetic, method calls, and — since the let/var slice —
/// statements with type-locked bindings (Design.md §2.2, §3, §13).
indirect enum Expr {
    case literal(Value)
    case variable(String)
    case array([Expr])
    case dictionary([(Expr, Expr)])
    case unaryMinus(Expr)
    case binary(Character, Expr, Expr)         // + - * /
    case method(Expr, name: String, args: [Expr], called: Bool)
}

/// A type annotation: `: Int` or `: Int?` (the flat optional of §3a —
/// `Int?` permits `nil` in the slot, it is not a wrapper type).
struct TypeAnnotation: Equatable {
    let name: String
    let optional: Bool
}

enum Stmt {
    case declaration(mutable: Bool, name: String, annotation: TypeAnnotation?, initializer: Expr)
    case assignment(name: String, expr: Expr)
    case expression(Expr)
}

struct Parser {
    private let tokens: [Token]
    private var pos = 0

    init(_ tokens: [Token]) {
        self.tokens = tokens
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

    /// Parses a whole program: statements separated by newlines or `;`.
    mutating func parseProgram() throws -> [Stmt] {
        var statements: [Stmt] = []
        skipSeparators()
        while pos < tokens.count {
            statements.append(try parseStatement())
            guard pos == tokens.count || consumeSeparator() else {
                throw SwiftalkError.syntax("expected a newline or ';' between statements")
            }
            skipSeparators()
        }
        guard !statements.isEmpty else {
            throw SwiftalkError.syntax("empty program")
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
        case .identifier(let name) where peek(at: 1) == .punct("="):
            pos += 2
            return .assignment(name: name, expr: try parseAdditive())
        default:
            return .expression(try parseAdditive())
        }
    }

    private mutating func parseDeclaration() throws -> Stmt {
        guard case .identifier(let keyword)? = advance() else { fatalError("unreachable") }
        let mutable = keyword == "var"
        guard case .identifier(let name)? = advance() else {
            throw SwiftalkError.syntax("expected a name after '\(keyword)'")
        }
        if ["let", "var", "true", "false", "nil"].contains(name) {
            throw SwiftalkError.syntax("'\(name)' is a keyword, not a name")
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
                            initializer: try parseAdditive())
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
        while case .punct(".")? = peek {
            pos += 1
            guard case .identifier(let name)? = advance() else {
                throw SwiftalkError.syntax("expected member name after '.'")
            }
            var args: [Expr] = []
            var called = false
            if case .punct("(")? = peek {
                called = true
                pos += 1
                if peek != .punct(")") {
                    repeat {
                        args.append(try parseAdditive())
                    } while consumeComma(closing: ")")
                }
                try expect(")")
            }
            expr = .method(expr, name: name, args: args, called: called)
        }
        return expr
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
        case .identifier("true"):  return .literal(.bool(true))
        case .identifier("false"): return .literal(.bool(false))
        case .identifier("nil"):   return .literal(.nil)
        case .identifier(let name) where name == "let" || name == "var":
            throw SwiftalkError.syntax("'\(name)' declaration is not an expression")
        case .identifier(let name):
            return .variable(name)
        case .punct("("):
            let inner = try parseAdditive()
            try expect(")")
            return inner
        case .punct("["):
            return try parseCollection()
        case let t:
            throw SwiftalkError.syntax("unexpected token \(t.map { "\($0)" } ?? "end of input")")
        }
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
        let first = try parseAdditive()
        if case .punct(":")? = peek {          // dictionary
            pos += 1
            var pairs: [(Expr, Expr)] = [(first, try parseAdditive())]
            while consumeComma(closing: "]") {
                let key = try parseAdditive()
                try expect(":")
                pairs.append((key, try parseAdditive()))
            }
            try expect("]")
            return .dictionary(pairs)
        }
        var elements = [first]                 // array
        while consumeComma(closing: "]") {
            elements.append(try parseAdditive())
        }
        try expect("]")
        return .array(elements)
    }
}
