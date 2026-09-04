import Testing
@testable import Swiftalk

@Suite("type inference: homogeneous collections, typed locks, hex floats (round 59)")
struct InferenceTests {
    @Test("[0,1,2,3] is [Int]; a mixed literal needs an annotation to bind")
    func arrayInference() throws {
        #expect(try eval("let ary = [0, 1, 2, 3]\nary") == .array([0, 1, 2, 3].map { .int($0) }))
        #expect(throws: SwiftalkError.self) { try eval("let bad = [0.0, 1, 2, 3]") }
        #expect(try eval("let ok: [Primitives] = [0.0, 1, 2, 3]\nok.count") == .int(4))
        #expect(try eval("let ok: Any = [0.0, 1, 2, 3]\nok") ==
            .array([.double(0.0), .int(1), .int(2), .int(3)]))
        // as an EXPRESSION a mixed literal still evaluates — only
        // binding without an annotation is the error
        #expect(try eval(#"[1, "one", 2.0].count"#) == .int(3))
        // a nil element makes the element lock optional since round 101: [Int?]
        #expect(try eval("var a = [1, nil]\na.append(nil)\na.count") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, nil]\na.append(\"s\")") }
        #expect(try eval("let a: [Int?] = [1, nil]\na.count") == .int(2))
    }

    @Test("the inferred element lock ENFORCES: [Int] rejects a String, deep")
    func elementLocks() throws {
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2]\na = [\"x\"]") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2]\na[0] = \"x\"") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2]\na.append(\"x\")") }
        #expect(try eval("var a = [1, 2]\na.append(3)\na") == .array([1, 2, 3].map { .int($0) }))
        // nested: [[Int]] all the way down
        #expect(try eval("var m = [[1, 2], [3]]\nm[1][0] = 30\nm")
            == .array([.array([.int(1), .int(2)]), .array([.int(30)])]))
        #expect(throws: SwiftalkError.self) { try eval("var m = [[1, 2], [3]]\nm[1][0] = \"x\"") }
    }

    @Test("dictionaries: [0: \"zero\"] is [Int: String] — a sparse array is a Dictionary")
    func dictionaryInference() throws {
        #expect(try eval("""
            let dict = [0: "zero", 1: "one"]
            [dict[1], dict[9]]
            """) == .array([.string("one"), .nil]))
        #expect(throws: SwiftalkError.self) { try eval(#"let d = [0: "zero", "one": 1]"#) }
        #expect(throws: SwiftalkError.self) { try eval(#"let d = [0: "zero", 1: 1]"#) }
        // round 35 upheld: nil is a right value for a key, storable
        // through a typed lock, and shaping nothing at inference
        #expect(try eval("""
            var d = [0: "zero", 1: nil]
            d[0] = nil
            d.has(0)
            """) == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval(#"var d = [0: "zero"]"# + "\nd[1] = 1") }
    }

    @Test("SION and Any as annotation vocabulary; Any unlocks retyping")
    func sionAndAny() throws {
        #expect(try eval("""
            let s: SION = [1, "one", Data([255]), .Date(0.0)]
            s.count
            """) == .int(4))
        // a Function is not SION-serializable
        #expect(throws: SwiftalkError.self) { try eval("let s: SION = [{ 1 }]") }
        #expect(try eval("var a: Any = 1\na = \"str\"\na") == .string("str"))
        #expect(try eval("var x: Any = nil\nx == nil") == .bool(true))
        // Primitives excludes Data/Date (they are SION's extras)
        #expect(throws: SwiftalkError.self) { try eval("let p: [Primitives] = [Data([1])]") }
    }

    @Test("1 is Int, 1.0 is Double — and so are 1e0 and 0x1p0")
    func literalTypes() throws {
        #expect(try eval("1.Type.name") == .string("Int"))
        #expect(try eval("1.0.Type.name") == .string("Double"))
        #expect(try eval("1e0.Type.name") == .string("Double"))
        #expect(try eval("1e3") == .double(1000))
        #expect(try eval("0x1p0.Type.name") == .string("Double"))
        #expect(try eval("0x1p0") == .double(1))
        #expect(try eval("0x1.fep7") == .double(255))
        #expect(try eval("0x1.8p-1") == .double(0.75))
        #expect(try eval("0xff") == .int(255))                   // still an Int
        #expect(try eval("0xff.description") == .string("255"))  // still member access
        // the round-37 debug round trip, closed: hex floats re-enter
        #expect(try eval(Value.double(0.1).sourceString(debug: true)) == .double(0.1))
    }

    @Test("annotations parse structurally: [T], [K: V], nested, optional")
    func annotationForms() throws {
        #expect(try eval("let a: [Int] = [1]\na") == .array([.int(1)]))
        #expect(try eval("let d: [String: [Int]] = [\"k\": [1, 2]]\nd[\"k\"]")
            == .array([.int(1), .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("let a: [Int] = [1.0]") }
        #expect(throws: SwiftalkError.self) { try eval("let a: [Wat] = [1]") }
        #expect(try eval("var a: [Int]? = nil\na = [1]\na") == .array([.int(1)]))
    }
}
