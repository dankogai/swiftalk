@testable import Swiftalk

// The public API is namespaced (Swiftalk.eval, Swiftalk.Interpreter, ...);
// tests keep the terse spellings via these shims. Value, Interpreter, and
// SwiftalkError come through @testable as the module's internal
// typealiases.
func eval(_ source: String) throws -> Value {
    try Swiftalk.eval(source)
}

func needsMoreInput(_ source: String) -> Bool {
    Swiftalk.needsMoreInput(source)
}
