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
        #expect(try eval("[.Date(0.0), Data(\"AQID\"), /a/, 1...].String(.pretty)")
                == .string("[\n  .Date(0.0),\n  .Data(\"AQID\"),\n  /a/,\n  1...\n]"))     // leaves stay on their line
    }

    private let decls = """
        struct Point { var x: Int = 0; var y: Int = 0 }
        struct Empty { }
        enum Shape { case circle(r: Double), square(Double), dot }

        """

    @Test("tuples, structs, and enum payloads open up too (round 118); the text re-enters")
    func composites() throws {
        #expect(try eval("(1, \"a\").String(.pretty)") == .string("(\n  1,\n  \"a\"\n)"))
        #expect(try eval("(x: 1, y: [2, 3]).String(.pretty)") == .string("(\n  x: 1,\n  y: [\n    2,\n    3\n  ]\n)"))
        #expect(try eval("(7,).String(.pretty)") == .string("(\n  7,\n)"))
        #expect(try eval("().String(.pretty)") == .string("()"))
        #expect(try eval(decls + "Point(x: 3, y: 4).String(.pretty)") == .string("Point(\n  x: 3,\n  y: 4\n)"))
        #expect(try eval(decls + "Empty().String(.pretty)") == .string("Empty()"))
        #expect(try eval(decls + "Shape.circle(r: 2.5).String(.pretty)") == .string("Shape.circle(\n  r: 2.5\n)"))
        #expect(try eval(decls + "Shape.square(1.0).String(.pretty)") == .string("Shape.square(\n  1.0\n)"))
        #expect(try eval(decls + "Shape.dot.String(.pretty)") == .string("Shape.dot"))
        #expect(try eval(decls + "[Point(x: 1, y: 2)].String(.pretty)") == .string("[\n  Point(\n    x: 1,\n    y: 2\n  )\n]"))
        // the pretty text is the source form: it re-enters where the types are declared
        let text = try eval(decls + "[(p: Point(x: 1, y: 2), s: Shape.circle(r: 1.0), t: (1, [2]))].String(.pretty)")
        guard case .string(let source) = text else { throw SwiftalkError.type("expected a String") }
        #expect(source.split(separator: "\n").count == 17)
        #expect(try eval(decls + "let back = " + source + "\nback == [(p: Point(x: 1, y: 2), s: Shape.circle(r: 1.0), t: (1, [2]))]") == .bool(true))
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
