import Testing
@testable import Swiftalk

/// Round 161: `r.catch { err in ... }` — a success unwraps as `??` does; a
/// failure runs the handler with the error and is its value.
@Suite("Result.catch { err in } (round 161)")
struct CatchTests {
    @Test("success unwraps without running the handler; failure runs it with the error")
    func semantics() throws {
        #expect(try eval(".success(2).catch { err in 0 }") == .int(2))
        #expect(try eval(".failure(\"boom\").catch { err in \"handled: \" + err }") == .string("handled: boom"))
        #expect(try eval(".failure(\"boom\").catch { \"handled: \" + $0 }") == .string("handled: boom"))
        #expect(try eval("var log = []\nlet v = .success(1).catch { log.append($0); 0 }\n[v, log.count]") == .array([.int(1), .int(0)]))   // not run
        #expect(try eval("var log = []\nlet v = .failure(\"e\").catch { log.append($0); 0 }\n[v, log.count]") == .array([.int(0), .int(1)]))
        #expect(try eval("eval(\"1 +\").catch { $0.count } > 0") == .bool(true))
        #expect(try eval("eval(\"6 * 7\").catch { _ in nil }") == .int(42))
        #expect(try eval("eval(\"6 *\").catch { _ in nil }") == .nil)
        #expect(try eval("[.success(1), .failure(\"e\")].map { $0.catch { _ in -1 } }") == .array([.int(1), .int(-1)]))
        #expect(try eval(".failure(\"e\").catch { err in .failure(\"re: \" + err) }.failure") == .string("re: e"))   // the handler may return a Result
        #expect(try eval("let halve = { n in n % 2 == 0 ? .success(n / 2) : .failure(\"odd\") }\nhalve(3).catch { _ in 0 } + halve(4).catch { _ in 0 }") == .int(2))
    }

    @Test("Result only, one Function")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("nil.catch { 0 }") }
        #expect(throws: SwiftalkError.self) { try eval("1.catch { 0 }") }
        #expect(throws: SwiftalkError.self) { try eval(".success(1).catch(0)") }
        #expect(throws: SwiftalkError.self) { try eval(".success(1).catch { 0 } { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval(".failure(\"e\").catch { a, b in 0 }") }      // the handler takes one argument
    }
}
