import Testing
@testable import Swiftalk

/// Round 160: `.success(v)` and `.failure(e)` construct a Result anywhere,
/// no annotation needed — Result being the one enum every program knows.
@Suite("bare .success(v) / .failure(e) construct a Result (round 160)")
struct BareResultCaseTests {
    @Test("in expressions, comparisons, closures, Arrays, and switch")
    func construct() throws {
        #expect(try eval(".success(\"hi\") == Result.success(\"hi\")") == .bool(true))
        #expect(try eval(".failure(\"e\").failure") == .string("e"))
        #expect(try eval("eval(\"1 + 1\") == .success(2)") == .bool(true))
        #expect(try eval("let halve = { n in n % 2 == 0 ? .success(n / 2) : .failure(\"odd: \\(n)\") }\n[halve(4).success, halve(3).failure]") == .array([.int(2), .string("odd: 3")]))
        #expect(try eval("let halve = { n in n % 2 == 0 ? .success(n / 2) : .failure(\"odd\") }\nlet quarter = { n in .success(halve(halve(n)?)?) }\n[quarter(8).success, quarter(6).failure]") == .array([.int(2), .string("odd")]))
        #expect(try eval("switch .failure(\"x\") { case let v = .success: v case let e = .failure: \"failed: \" + e }") == .string("failed: x"))
        #expect(try eval("[.success(1), .failure(\"e\")].map { $0.Type == Result }") == .array([.bool(true), .bool(true)]))
        #expect(try eval("let r: Result = .success(7)\nr == .success(7)") == .bool(true))          // the annotated form still works
        #expect(try eval(".success(1) ?? 0") == .int(1))
        #expect(try eval(".failure(\"e\") ?? 0") == .int(0))
    }

    @Test("a type's own member of the same name still wins inside its body; other bare calls are the errors they were")
    func boundaries() throws {
        #expect(try eval("struct S { var v = 1; let ok = { .success(.v) } }\nS().ok()") == (try eval("Result.success(1)")))   // no `success` member: a Result
        #expect(try eval("struct S { var v = 1; let success = { x in \"mine \\(x)\" }; let ok = { .success(.v) } }\nS().ok()") == .string("mine 1"))
        #expect(try eval(".hex") == .string("hex"))                                                    // uncalled: still a format word
        #expect(throws: SwiftalkError.self) { try eval(".nope(1)") }                                  // not a Result case: cannot call a String
        #expect(throws: SwiftalkError.self) { try eval(".success()") }                                // the payload is required
        #expect(throws: SwiftalkError.self) { try eval(".success(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("enum E { case a(Int) }\n.a(1)") }              // a user enum still needs its name or an annotation
    }
}
