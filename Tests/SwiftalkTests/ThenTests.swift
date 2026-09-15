import Testing
@testable import Swiftalk

/// Round 162: `r.then { v in ... }` — a success maps through the handler
/// and stays a Result (a Result the handler returns is taken as is); a
/// failure passes through, so a chain stops at the first failure.
@Suite("Result.then { v in } (round 162)")
struct ThenTests {
    @Test("success maps and re-wraps, or flattens a returned Result; failure passes through untouched")
    func semantics() throws {
        #expect(try eval(".success(2).then { v in v * 21 }") == (try eval("Result.success(42)")))
        #expect(try eval(".failure(\"boom\").then { v in v * 21 }") == (try eval("Result.failure(\"boom\")")))
        #expect(try eval("var ran = false\nlet r = .failure(\"e\").then { ran = true; 1 }\n[ran, r.failure]") == .array([.bool(false), .string("e")]))
        #expect(try eval("let halve = { n in n % 2 == 0 ? .success(n / 2) : .failure(\"odd: \\(n)\") }\n.success(8).then(halve).then(halve).success") == .int(2))
        #expect(try eval("let halve = { n in n % 2 == 0 ? .success(n / 2) : .failure(\"odd: \\(n)\") }\n.success(6).then(halve).then(halve).then(halve).failure") == .string("odd: 3"))
        #expect(try eval(".success(1).then { .failure(\"re\") }.failure") == .string("re"))         // a returned Result is not double-wrapped
        #expect(try eval(".success(1).then { nil }") == (try eval("Result.success(nil)")))         // a plain nil is a success of nil
        #expect(try eval("eval(\"6 * 7\").then { $0 + 1 }.catch { _ in 0 }") == .int(43))
        #expect(try eval("eval(\"6 *\").then { $0 + 1 }.catch { _ in 0 }") == .int(0))
        #expect(try eval("[.success(1), .failure(\"e\")].map { $0.then { $0 * 10 } }.map { $0.success }") == .array([.int(10), .nil]))
    }

    @Test("Result only, one Function")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("1.then { $0 }") }
        #expect(throws: SwiftalkError.self) { try eval("nil.then { $0 }") }
        #expect(throws: SwiftalkError.self) { try eval(".success(1).then(2)") }
        #expect(throws: SwiftalkError.self) { try eval(".success(1).then { a, b in 0 }") }
    }
}
