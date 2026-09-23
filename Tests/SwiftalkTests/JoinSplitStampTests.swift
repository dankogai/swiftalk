import Testing
@testable import Swiftalk

@Suite("joined() and split() keep the stamp (round 177)")
struct JoinSplitStampTests {
    @Test("split: a String's pieces are [String] even when none; an Array's pieces are Arrays of its element type, each stamped")
    func split() throws {
        #expect(try eval("\"\".split(\",\").Type.String()") == .string("[String]"))
        #expect(try eval("\"\".split(/,/).Type.String()") == .string("[String]"))
        #expect(try eval("\"\".split { $0 == \",\" }.Type.String()") == .string("[String]"))
        #expect(try eval("\"a,b\".split(\",\")") == .array([.string("a"), .string("b")]))
        #expect(try eval("[Int]().split(0).Type.String()") == .string("[[Int]]"))
        #expect(try eval("[1, 0, 2].split(0).Type.String()") == .string("[[Int]]"))
        #expect(try eval("[1, 0, 2].split(0)[0].Type.String()") == .string("[Int]"))
        #expect(try eval("(1...5).split(3).Type.String()") == .string("[[Int]]"))
        #expect(try eval("(1...5).split(3)") == .array([.array([.int(1), .int(2)]), .array([.int(4), .int(5)])]))
        #expect(try eval("Set<Int>().split(0).Type.String()") == .string("[Set<Int>]"))
        #expect(try eval("Data().split(0).Type.String()") == .string("[Data]"))
        #expect(try eval("[Int: String]().split { true }.Type.String()") == .string("[[Int: String]]"))
        #expect(try eval("[].split(0).Type.String()") == .string("[SION]"))                // no pieces, nothing known: the data default (round 181)
        #expect(throws: SwiftalkError.self) { try eval("var p = [Int]().split(0)\np.append([\"s\"])") }
        #expect(throws: SwiftalkError.self) { try eval("var p = [1, 0, 2].split(0)\np[0].append(\"s\")") }
    }

    @Test("joined: an empty [[Int]] joins to an empty [Int], not \"\"; a flattened Array carries the inner element type")
    func joined() throws {
        #expect(try eval("[[1], [2]].joined().Type.String()") == .string("[Int]"))
        #expect(try eval("[[Int]]().joined().Type.String()") == .string("[Int]"))
        #expect(try eval("[[Int]]().joined()") == .array([]))
        #expect(try eval("[[Int]]().joined([0]).Type.String()") == .string("[Int]"))
        #expect(try eval("[[1, 2], [3]].joined([0])") == .array([.int(1), .int(2), .int(0), .int(3)]))
        #expect(try eval("[[[Int]]]().joined().Type.String()") == .string("[[Int]]"))
        #expect(try eval("[String]().joined(\",\")") == .string(""))
        #expect(try eval("[\"a\", \"b\"].joined(\",\")") == .string("a,b"))
        #expect(try eval("[].joined()") == .string(""))                                        // nothing known: "" as before
        #expect(throws: SwiftalkError.self) { try eval("var j = [[Int]]().joined()\nj.append(\"s\")") }
        #expect(try eval("[[1], [\"a\"]].joined([0]).Type.String()") == .string("Array"))      // mixed inner: erased, still built
    }
}
