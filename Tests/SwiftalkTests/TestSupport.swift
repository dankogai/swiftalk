@testable import Swiftalk

// The public API is namespaced (Swiftalk.eval, Swiftalk.Interpreter, ...);
// tests keep the terse spellings via these shims. Value, Interpreter, and
// SwiftalkError come through @testable as the module's internal
// typealiases.
func eval(_ source: String) throws -> Value {
    try interpreter().eval(source)
}

/// A fresh Interpreter with the CLI's prelude (round 185): `print`,
/// `debugPrint`, `fetch`, `Response` bound as the CLI binds them.
func interpreter(relaxed: Bool = false) throws -> Interpreter {
    let i = Interpreter(relaxed: relaxed)
    try i.preimport()
    return i
}

func needsMoreInput(_ source: String) -> Bool {
    Swiftalk.needsMoreInput(source)
}
