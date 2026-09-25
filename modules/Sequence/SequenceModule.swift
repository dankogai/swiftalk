import Swiftalk

// `Sequence` — the module that extends the core type `Sequence` (round
// 192): `Sequence.zip(a, b)`, Swift's `zip` (round 174; a core static
// from round 185 until now). Pairs until the shorter side ends, as
// unlabeled 2-tuples: lazy when either side is a lazy Sequence (or
// `a...`), else an Array stamped `[Tuple]` — the one element type a zip
// can have, even when empty. Exports nothing by name; preimported by the
// CLI, `import from "Sequence"` otherwise.

func zip(_ args: [Swiftalk.Value]) throws -> Swiftalk.Value {
    guard args.count == 2 else { throw Swiftalk.Error.type("Sequence.zip(a, b) takes exactly two Sequences") }
    for side in args where !Swiftalk.conforms(side, to: "Sequence") {
        throw Swiftalk.Error.type("Sequence.zip(a, b): \(side.typeName) is not a Sequence")
    }
    let (lhs, rhs) = (args[0], args[1])
    let tuple = TypeAnnotation("Tuple")
    if Swiftalk.isLazy(lhs) || Swiftalk.isLazy(rhs) {
        return Swiftalk.sequence(of: tuple) {
            // the sides' pullers are made on the first pull (making one can
            // throw); a fresh pair per iteration keeps the zip re-iterable
            var sides: (() throws -> Swiftalk.Value?, () throws -> Swiftalk.Value?)? = nil
            return {
                if sides == nil { sides = (try Swiftalk.iterate(lhs), try Swiftalk.iterate(rhs)) }
                guard let a = try sides!.0(), let b = try sides!.1() else { return nil }
                return .tuple([a, b], labels: [nil, nil])
            }
        }
    }
    let a = try Swiftalk.iterate(lhs), b = try Swiftalk.iterate(rhs)
    var pairs: [Swiftalk.Value] = []
    while let x = try a(), let y = try b() { pairs.append(.tuple([x, y], labels: [nil, nil])) }
    return .array(pairs, lock: TypeAnnotation("Array", parameters: [tuple]))
}

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "Sequence")
    let zipFunction = Swiftalk.Module(name: "-")          // a Function value, made the way exports are
    zipFunction.function("zip", zip)
    m.static("Sequence", "zip", zipFunction.value(named: "zip")!)
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
