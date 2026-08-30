import Testing
@testable import Swiftalk

@Suite("Data and Date: the SION roster completed (round 50, §3b)")
struct DataDateTests {
    @Test("Data: bytes distinct from String, constructed from strings and byte arrays")
    func dataBasics() throws {
        #expect(try eval(#""café".Data()"#) == .data(Array("café".utf8)))
        #expect(try eval(#"Data("café") == "café".Data()"#) == .bool(true))   // round-47 law
        #expect(try eval("Data([255, 0, 128])") == .data([255, 0, 128]))
        #expect(try eval("Data()") == .data([]))
        #expect(try eval("Data([256])") == .nil)          // not a byte — failable
        #expect(try eval("Data([1, -1])") == .nil)
        #expect(throws: SwiftalkError.self) { try eval("Data(1.5)") }
        #expect(try eval(#""abc".Data().Type == Data"#) == .bool(true))
        #expect(try eval("Data.conforms(to: Hashable)") == .bool(true))
    }

    @Test("Data: count, byte subscripts, equality, dictionary keys")
    func dataAccess() throws {
        #expect(try eval(#""abc".Data().count"#) == .int(3))
        #expect(try eval(#""café".Data().count"#) == .int(5))   // bytes, not graphemes
        #expect(try eval("Data([10, 20, 30])[1]") == .int(20))
        #expect(throws: SwiftalkError.self) { try eval("Data([1])[9]") }
        #expect(try eval(#"[Data([1]): "one"][Data([1])]"#) == .string("one"))
    }

    @Test("Data round-trips: source form re-enters; .String(.utf8) decodes, failably")
    func dataRoundTrip() throws {
        #expect(try eval("Data([255, 1]).String()") == .string("Data([255, 1])"))
        #expect(try eval("Data([255, 1]).String(.quoted)") == .string("Data([255, 1])"))
        let v = try eval("Data([0, 127, 255])")
        #expect(try eval(v.sourceString()) == v)
        // decode: text comes back; junk comes back nil
        #expect(try eval(#""caf\u{E9}".Data().String(.utf8)"#) == .string("café"))
        #expect(try eval("Data([255, 254]).String(.utf8)") == .nil)
        #expect(try eval("Data([255]).debugDescription") == .string("Data([0xff])"))
    }

    @Test("Date: an epoch Double in SION's clothing")
    func dateBasics() throws {
        #expect(try eval("Date(0.0)") == .date(0))
        #expect(try eval("Date(1234567890)") == .date(1234567890))
        #expect(try eval("Date(1.5).Type == Date") == .bool(true))
        #expect(try eval("Double(Date(1.5))") == .double(1.5))
        #expect(try eval("Date(2.5).Double()") == .double(2.5))   // the law
        #expect(throws: SwiftalkError.self) { try eval("Date(\"tomorrow\")") }
        // Date() is now — a plausible epoch, monotonic-ish
        #expect(try eval("Date() < Date(9999999999.0)") == .bool(true))
        #expect(try eval("Date(0.0) < Date()") == .bool(true))
    }

    @Test("Date: Comparable and Equatable, as §10 promised")
    func dateComparisons() throws {
        #expect(try eval("Date(1.0) < Date(2.0)") == .bool(true))
        #expect(try eval("Date(2.0) >= Date(2.0)") == .bool(true))
        #expect(try eval("Date(1.0) == Date(1.0)") == .bool(true))
        #expect(try eval("Date.conforms(to: Comparable)") == .bool(true))
        #expect(try eval("Data.conforms(to: Comparable)") == .bool(false))
        #expect(throws: SwiftalkError.self) { try eval("Date(1.0) < 2.0") }   // Date ≠ Double
    }

    @Test("Date round-trips in SION's own spelling: .Date(epoch)")
    func dateRoundTrip() throws {
        #expect(try eval("Date(255.5).String()") == .string(".Date(255.5)"))
        let v = try eval("Date(1234567890.5)")
        #expect(try eval(v.sourceString()) == v)               // .Date(...) re-enters
        // (the debug form uses hex-float notation, as SION does —
        // re-entering it awaits hex-float literals in the lexer, OPEN)
        #expect(v.sourceString(debug: true).hasPrefix(".Date(0x"))
        #expect(try eval(".Date(42.0)") == .date(42))          // the SION spelling, directly
    }

    @Test("annotations and locks: var d: Data, var t: Date")
    func locks() throws {
        #expect(try eval("var d: Data = Data()\nd = Data([1])\nd.count") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("var d: Data = Data()\nd = \"s\"") }
        #expect(try eval("var t: Date = Date(0.0)\nt = Date(1.0)\nt < Date(2.0)") == .bool(true))
    }
}
