import Testing
@testable import Swiftalk

@Suite("Data: Range subscripts, reading and writing, and byte writes (round 92)")
struct DataSliceTests {
    @Test("d[1..<3], d[1...] give a Data; Swift's bounds rule; the source is untouched")
    func read() throws {
        #expect(try eval("\"hello\".Data()[1..<3]") == .data([101, 108]))
        #expect(try eval("\"hello\".Data()[3...]") == .data([108, 111]))
        #expect(try eval("\"hello\".Data()[1..<3].String(.utf8)") == .string("el"))
        #expect(try eval("\"hello\".Data()[5...]") == .data([]))
        #expect(try eval("\"hello\".Data()[1..<3].Type == Data") == .bool(true))
        #expect(try eval("let d = Data([1, 2, 3])\nlet e = d[1...]\nd") == .data([1, 2, 3]))
        #expect(throws: SwiftalkError.self) { try eval("\"hello\".Data()[2...9]") }
        #expect(throws: SwiftalkError.self) { try eval("\"hello\".Data()[-1...1]") }
        #expect(throws: SwiftalkError.self) { try eval("\"hello\".Data()[\"x\"]") }
    }

    @Test("d[0..<1] = Data(...) is replaceSubrange; d[i] = byte writes one byte in 0...255")
    func write() throws {
        #expect(try eval("var d = \"hello\".Data()\nd[0] = 72\nd.String(.utf8)") == .string("Hello"))
        #expect(try eval("var d = \"hello\".Data()\nd[1...] = \"i!\".Data()\nd.String(.utf8)") == .string("hi!"))
        #expect(try eval("var d = Data([1, 2, 3])\nd[d.count...] = Data([4])\nd") == .data([1, 2, 3, 4]))
        #expect(try eval("var d = Data([1, 2, 3])\nd[0..<2] = Data()\nd") == .data([3]))
        #expect(try eval("var d = Data([1, 2, 3])\nd[1..<1] = Data([9, 9])\nd") == .data([1, 9, 9, 2, 3]))
        #expect(try eval("var d = Data([1, 2, 3])\nd[2] = 255\nd") == .data([1, 2, 255]))
        #expect(try eval("var s = [\"k\": Data([1, 2])]\ns[\"k\"][0] = 0\ns[\"k\"]") == .data([0, 2]))
        #expect(throws: SwiftalkError.self) { try eval("var d = Data([1])\nd[0..<1] = [9]") }
        #expect(throws: SwiftalkError.self) { try eval("var d = Data([1])\nd[0] = 256") }
        #expect(throws: SwiftalkError.self) { try eval("var d = Data([1])\nd[0] = -1") }
        #expect(throws: SwiftalkError.self) { try eval("var d = Data([1])\nd[0] = \"x\"") }
        #expect(throws: SwiftalkError.self) { try eval("var d = Data([1])\nd[3...] = Data()") }
        #expect(throws: SwiftalkError.self) { try eval("let d = Data([1])\nd[0] = 9") }
    }
}
