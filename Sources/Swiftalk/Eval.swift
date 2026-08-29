/// Milestone 0: `eval()` — source string in, value out (Design.md §13).
public func eval(_ source: String) throws -> Value {
    var lexer = Lexer(source)
    var parser = Parser(try lexer.tokenize())
    return try evaluate(try parser.parseExpression())
}

func evaluate(_ expr: Expr) throws -> Value {
    switch expr {
    case .literal(let v):
        return v
    case .array(let elements):
        return .array(try elements.map(evaluate))
    case .dictionary(let pairs):
        var dict: [Value: Value] = [:]
        for (k, v) in pairs {
            dict[try evaluate(k)] = try evaluate(v)
        }
        return .dictionary(dict)
    case .unaryMinus(let e):
        switch try evaluate(e) {
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
        return try binary(op, try evaluate(lhs), try evaluate(rhs))
    case .method(let receiver, let name, let args, let called):
        return try method(on: try evaluate(receiver), name: name, args: try args.map(evaluate), called: called)
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
