/// Milestone-0 AST: literal expressions, collections, unary minus,
/// same-type arithmetic, and method calls (Design.md §13, milestone 0).
indirect enum Expr {
    case literal(Value)
    case array([Expr])
    case dictionary([(Expr, Expr)])
    case unaryMinus(Expr)
    case binary(Character, Expr, Expr)         // + - * /
    case method(Expr, name: String, args: [Expr], called: Bool)
}

struct Parser {
    private let tokens: [Token]
    private var pos = 0

    init(_ tokens: [Token]) {
        self.tokens = tokens
    }

    private var peek: Token? { pos < tokens.count ? tokens[pos] : nil }
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

    /// Parses a single expression and requires end of input.
    mutating func parseExpression() throws -> Expr {
        let expr = try parseAdditive()
        guard pos == tokens.count else {
            throw SwiftalkError.syntax("unexpected trailing tokens")
        }
        return expr
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
                    } while consumeComma()
                }
                try expect(")")
            }
            expr = .method(expr, name: name, args: args, called: called)
        }
        return expr
    }

    private mutating func consumeComma() -> Bool {
        if case .punct(",")? = peek {
            pos += 1
            return true
        }
        return false
    }

    private mutating func parsePrimary() throws -> Expr {
        switch advance() {
        case .int(let i):     return .literal(.int(i))
        case .double(let d):  return .literal(.double(d))
        case .string(let s):  return .literal(.string(s))
        case .identifier("true"):  return .literal(.bool(true))
        case .identifier("false"): return .literal(.bool(false))
        case .identifier("nil"):   return .literal(.nil)
        case .identifier(let name):
            throw SwiftalkError.syntax("unknown identifier '\(name)' (no variables yet in milestone 0)")
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
            while consumeComma() {
                let key = try parseAdditive()
                try expect(":")
                pairs.append((key, try parseAdditive()))
            }
            try expect("]")
            return .dictionary(pairs)
        }
        var elements = [first]                 // array
        while consumeComma() {
            elements.append(try parseAdditive())
        }
        try expect("]")
        return .array(elements)
    }
}
