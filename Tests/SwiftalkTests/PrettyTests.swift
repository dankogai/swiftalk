import Testing
@testable import Swiftalk

@Suite(".String(.pretty) — the source form, one element per line (round 117)")
struct PrettyTests {
    @Test("Arrays and Dictionaries open up, two spaces a level; scalars do not")
    func sion() throws {
        #expect(try eval("[0, 1, 2, 3].String(.pretty)") == .string("[\n  0,\n  1,\n  2,\n  3\n]"))
        #expect(try eval("[\"b\": [1, 2], \"a\": [:]].String(.pretty)")
                == .string("[\n  \"a\": [:],\n  \"b\": [\n    1,\n    2\n  ]\n]"))
        #expect(try eval("[1, [2, [3]]].String(.sion, .pretty)")
                == .string("[\n  1,\n  [\n    2,\n    [\n      3\n    ]\n  ]\n]"))
        #expect(try eval("[].String(.pretty)") == .string("[]"))
        #expect(try eval("[:].String(.pretty)") == .string("[:]"))
        #expect(try eval("42.String(.pretty)") == .string("42"))
        #expect(try eval("\"hi\".String(.pretty)") == .string("\"hi\""))
        #expect(try eval("[(1, 2)].String(.pretty)") == .string("[\n  (1, 2)\n]"))     // only Arrays and Dictionaries open
    }

    @Test("it is still SION: SION(text) reads it back")
    func roundTrip() throws {
        let doc = "let doc: SION = [\"n\": 42, \"tags\": [\"a\", \"b\"], \"none\": nil, \"bytes\": Data(\"AQID\"), 1: [[:]]]\n"
        #expect(try eval(doc + "SION(doc.String(.pretty)) == doc") == .bool(true))
        #expect(try eval(doc + "doc.String(.pretty).split(\"\\n\").count") == .int(12))
        #expect(try eval(doc + "doc.String(.quoted, .pretty) == doc.String(.pretty)") == .bool(true))
    }

    @Test("JSON: .String(.json, .pretty), in either order; property lists are already laid out")
    func json() throws {
        #expect(try eval("[\"b\": [1, 2], \"a\": [:]].String(.json, .pretty)")
                == .string("{\n  \"a\": {},\n  \"b\": [\n    1,\n    2\n  ]\n}"))
        #expect(try eval("[0, 1].String(.pretty, .json)") == .string("[\n  0,\n  1\n]"))
        #expect(try eval("[].String(.json, .pretty)") == .string("[]"))
        #expect(try eval("[\"k\": [1, nil]].String(.json)") == .string("{\"k\":[1,null]}"))       // compact, as before
        let doc = "let doc: SION = [\"n\": 42, \"tags\": [\"a\", \"b\"], \"none\": nil]\n"
        #expect(try eval(doc + "SION(json: doc.String(.json, .pretty)) == doc") == .bool(true))
        #expect(try eval("[\"n\": 42].String(.propertyList, .pretty) == [\"n\": 42].String(.propertyList)") == .bool(true))
    }

    @Test(".pretty with a number format, twice, or two formats is an error")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("255.String(.hex, .pretty)") }
        #expect(throws: SwiftalkError.self) { try eval("255.String(.pretty, radix: 16)") }
        #expect(throws: SwiftalkError.self) { try eval("[1].String(.pretty, .pretty)") }
        #expect(throws: SwiftalkError.self) { try eval("[1].String(.json, .sion)") }
    }
}
