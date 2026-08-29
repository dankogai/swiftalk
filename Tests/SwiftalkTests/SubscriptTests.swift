import Testing
@testable import Swiftalk

@Suite("subscripts: a[i], d[k], and $0 as $[0]")
struct SubscriptTests {
    @Test("array reads: Int index, trapping out of range (Swift-faithful)")
    func arrayReads() throws {
        #expect(try eval("[10, 20, 30][1]") == .int(20))
        #expect(try eval("let a = [1, 2, 3]\na[0] + a[2]") == .int(4))
        #expect(try eval("[[1], [2, 3]][1][0]") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("[1, 2][2]") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2][-1]") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2][\"0\"]") }
    }

    @Test("dictionary reads are flat-optional: missing key is nil (§3a)")
    func dictionaryReads() throws {
        #expect(try eval("[\"a\": 1][\"a\"]") == .int(1))
        #expect(try eval("[\"a\": 1][\"b\"]") == .nil)
        #expect(try eval("[\"a\": 1][\"b\"] == nil") == .bool(true))
        #expect(try eval("[1: \"one\", true: \"yes\"][true]") == .string("yes"))   // non-String keys
        #expect(try eval("let d = [\"k\": [1, 2]]\nd[\"k\"][1]") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1][\"b\"][0]") }   // cannot subscript Nil
    }

    @Test("subscripting non-collections errors; String stays undecided (§11)")
    func badReceivers() throws {
        #expect(throws: SwiftalkError.self) { try eval("42[0]") }
        #expect(throws: SwiftalkError.self) { try eval("\"abc\"[0]") }
    }

    @Test("array writes: in place through var, trapping out of range")
    func arrayWrites() throws {
        #expect(try eval("var a = [1, 2, 3]\na[1] = 20\na") == .array([.int(1), .int(20), .int(3)]))
        #expect(try eval("var a = [1]\na[0] = a[0] + 41\na[0]") == .int(42))
        #expect(throws: SwiftalkError.self) { try eval("var a = [1]\na[1] = 2") }
        #expect(throws: SwiftalkError.self) { try eval("let a = [1]\na[0] = 2") }  // let is immutable
    }

    @Test("dictionary writes: insert, update — and d[k] = nil deletes (round 15)")
    func dictionaryWrites() throws {
        #expect(try eval("var d = [\"a\": 1]\nd[\"b\"] = 2\nd.count") == .int(2))
        #expect(try eval("var d = [\"a\": 1]\nd[\"a\"] = 9\nd[\"a\"]") == .int(9))
        #expect(try eval("var d = [\"a\": 1, \"b\": 2]\nd[\"a\"] = nil\nd.count") == .int(1))
        #expect(try eval("var d = [\"a\": 1]\nd[\"a\"] = nil\nd") == .dictionary([:]))
    }

    @Test("nested writes rebuild the path")
    func nestedWrites() throws {
        #expect(try eval("var m = [[1, 2], [3, 4]]\nm[1][0] = 30\nm")
            == .array([.array([.int(1), .int(2)]), .array([.int(30), .int(4)])]))
        #expect(try eval("var d = [\"a\": [1, 2]]\nd[\"a\"][0] = 9\nd[\"a\"]")
            == .array([.int(9), .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("var d = [:]\nd[\"a\"][0] = 9") }
    }

    @Test("COW value semantics: a copy is a copy (§4)")
    func valueSemantics() throws {
        #expect(try eval("var a = [1, 2]\nlet b = a\na[0] = 9\nb") == .array([.int(1), .int(2)]))
        #expect(try eval("var a = [1, 2]\nlet b = a\na[0] = 9\na") == .array([.int(9), .int(2)]))
    }

    @Test("$0 is literally $[0] (§2.4)")
    func dollarIsSubscript() throws {
        #expect(try eval("{ $[0] + $[1] }(40, 2)") == .int(42))
        #expect(try eval("{ $0 + $1 }(40, 2)") == .int(42))            // same thing
        #expect(try eval("let i = 1\n{ $[i] }(\"a\", \"b\")") == .string("b"))  // computed index
        #expect(throws: SwiftalkError.self) { try eval("{ $2 }(1, 2)") }        // out of range
        #expect(throws: SwiftalkError.self) { try eval("{ $0 = 1 }(0)") }       // $ is immutable
    }
}
