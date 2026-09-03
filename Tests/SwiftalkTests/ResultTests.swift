import Testing
@testable import Swiftalk

@Suite("Result and the ?/! operator family (§8, §3a, round 51)")
struct ResultTests {
    @Test("Result is a built-in enum: construction, accessors, switch, equality")
    func resultBasics() throws {
        #expect(try eval("Result.success(42).success") == .int(42))
        #expect(try eval("Result.success(42).failure") == .nil)
        #expect(try eval("Result.failure(\"boom\").failure") == .string("boom"))
        #expect(try eval("Result.success(1) == Result.success(1)") == .bool(true))
        #expect(try eval("Result.success(1) == Result.failure(1)") == .bool(false))
        #expect(try eval("Result.success(1).Type == Result") == .bool(true))
        #expect(try eval("Result.success([1, 2]).String()") == .string("Result.success([1, 2])"))
        #expect(try eval("""
            var out = ""
            switch Result.failure("e") {
            case let v = .success: out = "ok"
            case let e = .failure: out = e
            }
            out
            """) == .string("e"))
        #expect(try eval("let r: Result = .success(7)\nr.success") == .int(7))
        #expect(throws: SwiftalkError.self) { try eval("Result(1)") }   // via .success/.failure
    }

    @Test("postfix ?: unwraps success, early-returns failure — the §8 marquee chain")
    func propagation() throws {
        let halve = """
            let halve = { n in n / 2 * 2 == n ? Result.success(n / 2) : Result.failure("odd: \\(n)") }
            """
        let ok = try eval("\(halve)\nlet quarter = { n in Result.success(halve(halve(n)?)?) }\nquarter(8)")
        #expect(ok == (try eval("Result.success(2)")))
        let bad = try eval("\(halve)\nlet quarter = { n in Result.success(halve(halve(n)?)?) }\nquarter(6)")
        #expect(bad == (try eval("Result.failure(\"odd: 3\")")))
    }

    @Test("postfix ?: nil early-returns too — one rule for absence and failure (§3a)")
    func nilPropagation() throws {
        #expect(try eval("let f = { x in x? + 1 }\nf(nil)") == .nil)
        #expect(try eval("let f = { x in x? + 1 }\nf(41)") == .int(42))
        #expect(try eval("let d = [\"k\": 2]\nlet f = { key in d[key]? * 10 }\nf(\"k\")") == .int(20))
        #expect(try eval("let d = [\"k\": 2]\nlet f = { key in d[key]? * 10 }\nf(\"x\")") == .nil)
        // outside a function there is nowhere to return to
        #expect(throws: SwiftalkError.self) { try eval("nil?") }
    }

    @Test("postfix !: for when the scripter is sure — trapping when wrong")
    func forceUnwrap() throws {
        #expect(try eval("Result.success(9)!") == .int(9))
        #expect(try eval("let d = [\"k\": 1]\nd[\"k\"]! + 1") == .int(2))
        #expect(try eval("42!") == .int(42))                       // already unwrapped (flat)
        #expect(throws: SwiftalkError.self) { try eval("nil!") }
        #expect(throws: SwiftalkError.self) { try eval("Result.failure(\"why\")!") }
        #expect(throws: SwiftalkError.self) { try eval("let d = [:]\nd[\"missing\"]!") }
    }

    @Test("?? defaults on nil and failure; unwraps success; stays lazy on the right")
    func coalescing() throws {
        #expect(try eval("nil ?? 5") == .int(5))
        #expect(try eval("3 ?? 5") == .int(3))
        #expect(try eval("Result.failure(\"e\") ?? 9") == .int(9))
        #expect(try eval("Result.success(4) ?? 9") == .int(4))
        #expect(try eval("let d = [\"a\": 1]\nd[\"x\"] ?? d[\"a\"] ?? 0") == .int(1))
        #expect(try eval("var hit = false\nlet f = { hit = true\n0 }\nlet v = 1 ?? f()\nhit") == .bool(false))
        #expect(try eval("var hit = false\nlet f = { hit = true\n7 }\nlet v = nil ?? f()\n[v, hit]")
            == .array([.int(7), .bool(true)]))
    }

    @Test("?. skips on nil, member and call alike; arguments stay unevaluated")
    func optionalChaining() throws {
        #expect(try eval("let d = [\"k\": [1, 2]]\nd[\"k\"]?.count") == .int(2))
        #expect(try eval("let d = [\"k\": [1, 2]]\nd[\"x\"]?.count") == .nil)
        #expect(try eval("nil?.count") == .nil)
        #expect(try eval("let d = [\"k\": \"foo\"]\nd[\"k\"]?.String(.quoted)") == .string("\"foo\""))
        #expect(try eval("var hit = false\nlet f = { hit = true\n0 }\nnil?.String(f())\nhit") == .bool(false))
        // chains of ?. compose
        #expect(try eval("let d = [\"a\": [\"b\": [1]]]\nd[\"a\"]?[\"b\"] == nil ? nil : d[\"a\"]![\"b\"]?.count")
            == .int(1))
    }

    @Test("the whole family, working one example: lookups with graceful degradation")
    func familyTogether() throws {
        #expect(try eval("""
            let ages = ["alice": 42]
            let describe = { name in
                let age = ages[name]?
                return "\\(name) is \\(age)"
            }
            [describe("alice") ?? "unknown", describe("bob") ?? "unknown"]
            """) == .array([.string("alice is 42"), .string("unknown")]))
    }
}
