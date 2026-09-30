import Testing
@testable import Swiftalk

// Round 204: `Bool(x)` takes a Bool or the two Strings, nothing else —
// `Bool(i)` as `i != 0` (round 105) is gone: `i != 0` is what it meant.

@Suite("Bool(): a Bool, \"true\", \"false\" — and nothing else (round 204)")
struct BoolConversionTests {
    @Test("what converts")
    func converts() throws {
        #expect(try eval("Bool()") == .bool(false))
        #expect(try eval("Bool(true)") == .bool(true))
        #expect(try eval("Bool(false)") == .bool(false))
        #expect(try eval("Bool(\"true\")") == .bool(true))
        #expect(try eval("Bool(\"false\")") == .bool(false))
        #expect(try eval("\"true\".Bool()") == .bool(true))
        #expect(try eval("Bool(\"yes\")") == .nil)                   // failable, as ever
        #expect(try eval("Bool(\"True\")") == .nil)
    }

    @Test("what does not: an Int names the idiom, the rest the type")
    func refuses() throws {
        #expect(throws: SwiftalkError.self) { try eval("Bool(1)") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(0)") }
        #expect(throws: SwiftalkError.self) { try eval("0.Bool()") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(1.0)") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(nil)") }
        #expect(throws: SwiftalkError.self) { try eval("Bool([true])") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(Byte(1))") }
        #expect(try eval("eval(\"Bool(1)\") == .failure(\"type error: cannot convert Int to Bool — write i != 0\")") == .bool(true))
        #expect(try eval("let i = 3\ni != 0") == .bool(true))
    }

    @Test(".Bool() is a String's parse and nothing else's (round 205) — the law's first exception")
    func methodOnStringOnly() throws {
        #expect(try eval("\"true\".Bool()") == .bool(true))
        #expect(try eval("\"false\".Bool()") == .bool(false))
        #expect(try eval("\"maybe\".Bool()") == .nil)
        #expect(try eval("\"true\".Bool() ?? false") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("true.Bool()") }        // a Bool is a Bool already
        #expect(throws: SwiftalkError.self) { try eval("1.Bool()") }
        #expect(throws: SwiftalkError.self) { try eval("let B = Bool\ntrue.B()") }   // the alias path too (round 111)
        #expect(try eval("Bool(true)") == .bool(true))                       // the constructor is untouched
        #expect(try eval("let B = Bool\nB(false)") == .bool(false))
        #expect(try eval("eval(\"true.Bool()\") == .failure(\"unknown member: Bool.Bool() — .Bool() is a String's parse; a Bool is a Bool already, and an Int is not one (i != 0)\")") == .bool(true))
    }

    @Test(".Int() and .Double() likewise (round 206): a String's parses; the constructors convert")
    func intAndDoubleOnStringOnly() throws {
        #expect(try eval("\"42\".Int()") == .int(42))
        #expect(try eval("\"1.5\".Double()") == .double(1.5))
        #expect(try eval("\"x\".Int() ?? -1") == .int(-1))
        #expect(try eval("Int(3.9)") == .int(3))
        #expect(try eval("Double(2)") == .double(2))
        #expect(try eval("Int(Byte(7))") == .int(7))
        #expect(try eval("Double(Date(1.5))") == .double(1.5))
        #expect(throws: SwiftalkError.self) { try eval("3.9.Int()") }
        #expect(throws: SwiftalkError.self) { try eval("2.Double()") }
        #expect(throws: SwiftalkError.self) { try eval("2.Int()") }               // not even the identity
        #expect(throws: SwiftalkError.self) { try eval("Byte(7).Int()") }
        #expect(throws: SwiftalkError.self) { try eval("Date(1.5).Double()") }
        #expect(throws: SwiftalkError.self) { try eval("let D = Double\n2.D()") }
        #expect(try eval("eval(\"2.Double()\") == .failure(\"unknown member: Int.Double() — .Double() is a String's parse; Double(x) converts\")") == .bool(true))
        // a type's own member of the name is the type's (round 151), and so is an extension's
        #expect(try eval("struct T { var k: Double; let Double = { .k - 1.0 } }\nT(k: 3.0).Double()") == .double(2))
        #expect(try eval("extension Int { let Double = { 0.5 } }\n7.Double()") == .double(0.5))
    }

    @Test(".Byte() likewise (round 207): a String's parse; Byte(x) converts")
    func byteOnStringOnly() throws {
        #expect(try eval("\"255\".Byte()") == .byte(255))
        #expect(try eval("\"0xff\".Byte()") == .byte(255))
        #expect(try eval("\"256\".Byte()") == .nil)
        #expect(try eval("\"x\".Byte() ?? Byte(0)") == .byte(0))
        #expect(try eval("Byte(7)") == .byte(7))
        #expect(try eval("Byte(7.9)") == .byte(7))
        #expect(try eval("Byte(Byte(7))") == .byte(7))
        #expect(throws: SwiftalkError.self) { try eval("7.Byte()") }
        #expect(throws: SwiftalkError.self) { try eval("7.9.Byte()") }
        #expect(throws: SwiftalkError.self) { try eval("Byte(7).Byte()") }
        #expect(throws: SwiftalkError.self) { try eval("let B = Byte\n7.B()") }
        #expect(try eval("eval(\"7.Byte()\") == .failure(\"unknown member: Int.Byte() — .Byte() is a String's parse; Byte(x) converts\")") == .bool(true))
    }

    @Test(".Data() likewise (round 208): a String's base64 parse and .utf8 encoding; Data(x) and Data(x, .propertyList) convert")
    func dataOnStringOnly() throws {
        #expect(try eval("\"AQID\".Data()") == .data([1, 2, 3]))
        #expect(try eval("\"hi\".Data(.utf8)") == .data([104, 105]))
        #expect(try eval("\"***\".Data() == nil") == .bool(true))
        #expect(try eval("Data([1, 2])") == .data([1, 2]))
        #expect(try eval("Data([Byte(255)])") == .data([255]))
        #expect(try eval("Data(\"x\", .propertyList)[0..<6].String(.utf8)") == .string("bplist"))
        #expect(try eval("Data(Data([9]))") == .data([9]))
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].Data()") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].Data(.propertyList)") }
        #expect(throws: SwiftalkError.self) { try eval("Data([9]).Data()") }
        #expect(throws: SwiftalkError.self) { try eval("42.Data(.utf8)") }
        #expect(throws: SwiftalkError.self) { try eval("let D = Data\n[1].D()") }
        #expect(try eval("eval(\"[1].Data()\") == .failure(\"unknown member: Array.Data() — .Data() is a String's parse; Data(x) converts\")") == .bool(true))
    }

    @Test(".Date() likewise (round 209): a String's ISO 8601 parse, new with the rule; Date(x) converts")
    func dateOnStringOnly() throws {
        #expect(try eval("\"1970-01-01T00:00:00Z\".Date()") == .date(0))
        #expect(try eval("\"1970-01-01\".Date()") == .nil)
        #expect(try eval("Date(0)") == .date(0))
        #expect(try eval("Date(Date(1.0))") == .date(1))
        #expect(throws: SwiftalkError.self) { try eval("0.Date()") }
        #expect(throws: SwiftalkError.self) { try eval("0.0.Date()") }
        #expect(throws: SwiftalkError.self) { try eval("let D = Date\n0.D()") }
        #expect(try eval("eval(\"0.Date()\") == .failure(\"unknown member: Int.Date() — .Date() is a String's parse; Date(x) converts\")") == .bool(true))
    }
}
