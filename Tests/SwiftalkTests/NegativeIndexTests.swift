import Testing
@testable import Swiftalk

// Round 194: a negative Int subscript counts from the end — a[-1] is
// a[a.count - 1] — on Arrays and Data, reading and writing.
struct NegativeIndexTests {
    @Test("reads: a[-1] is the last, a[-count] the first; past the front is the usual error")
    func reads() throws {
        #expect(try eval("[10, 20, 30][-1]") == .int(30))
        #expect(try eval("[10, 20, 30][-3]") == .int(10))
        #expect(try eval("let a = [1, 2, 3]\na[-1] + a[-2]") == .int(5))
        #expect(try eval("[[1, 2], [3, 4]][-1][-1]") == .int(4))
        #expect(try eval("Data([1, 2, 3])[-1]") == .byte(3))
        #expect(throws: SwiftalkError.self) { try eval("[10, 20, 30][-4]") }
        #expect(throws: SwiftalkError.self) { try eval("[][-1]") }
        #expect(throws: SwiftalkError.self) { try eval("[10, 20, 30][3]") }
        #expect(throws: SwiftalkError.self) { try eval("Data()[-1]") }
        do {
            _ = try eval("[10, 20, 30][-4]")
        } catch let error as SwiftalkError {
            #expect(error.description == "type error: index -4 out of range (count 3)")
        }
    }

    @Test("writes: a[-1] = v, compound forms, nested paths, Data bytes; Ranges keep Swift's rule")
    func writes() throws {
        #expect(try eval("var a = [1, 2, 3]\na[-1] = 9\na") == .array([.int(1), .int(2), .int(9)]))
        #expect(try eval("var a = [1, 2, 3]\na[-3] += 10\na") == .array([.int(11), .int(2), .int(3)]))
        #expect(try eval("var m = [[1, 2], [3, 4]]\nm[-1][-1] = 0\nm") == .array([.array([.int(1), .int(2)]), .array([.int(3), .int(0)])]))
        #expect(try eval("var d = Data([1, 2, 3])\nd[-1] = 255\nd") == .data([1, 2, 255]))
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2, 3]\na[-4] = 0") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2, 3]\na[-1] = \"x\"") }          // the lock still holds
        #expect(throws: SwiftalkError.self) { try eval("[1, 2, 3][-2...]") }                          // a Range subscript stays Swift's
        #expect(try eval("let a = [1, 2, 3]\na[1...]") == .array([.int(2), .int(3)]))
    }
}
