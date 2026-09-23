import Testing
@testable import Swiftalk

// Round 181: an empty container bound without an annotation is data —
// `[]` is `[SION]`, `[:]` is `[SION: SION]`, `Set()` is `Set<SION>`;
// `Primitives` is retired, SION covering its roster and more.
struct EmptyDefaultTests {
    @Test("the empty literals and erased constructors read as the data default")
    func defaults() throws {
        #expect(try eval("[].Type.String()") == .string("[SION]"))
        #expect(try eval("[:].Type.String()") == .string("[SION: SION]"))
        #expect(try eval("Set().Type.String()") == .string("Set<SION>"))
        #expect(try eval("Array().Type.String()") == .string("[SION]"))
        #expect(try eval("Dictionary().Type.String()") == .string("[SION: SION]"))
        #expect(try eval("var a = []\na.Type.String()") == .string("[SION]"))
        #expect(try eval("var d = [:]\nd.Type.String()") == .string("[SION: SION]"))
        #expect(try eval("struct S { var items = [] }\nS().items.Type.String()") == .string("[SION]"))
        #expect(try eval("[].Type.Element == SION") == .bool(true))
        #expect(try eval("[:].Type.Key == SION && [:].Type.Value == SION") == .bool(true))
        #expect(try eval("[].Type.Element(json: \"[1]\")") == .array([.int(1)]))
    }

    @Test("the default admits data and refuses the rest, element-deep")
    func enforces() throws {
        #expect(try eval("var a = []\na.append(1, \"s\", 2.0, true, nil, Data([1]), [1], [\"k\": 1])\na.count") == .int(8))
        #expect(throws: SwiftalkError.self) { try eval("var a = []\na.append({ $0 })") }
        #expect(throws: SwiftalkError.self) { try eval("var a = []\na.append(0..<3)") }
        #expect(throws: SwiftalkError.self) { try eval("var a = []\na.append((1, 2))") }
        #expect(throws: SwiftalkError.self) { try eval("struct P { var x = 0 }\nvar a = []\na.append(P())") }
        #expect(throws: SwiftalkError.self) { try eval("var d = [:]\nd[{ $0 }] = 1") }
        #expect(throws: SwiftalkError.self) { try eval("var d = [:]\nd[1] = { $0 }") }
        #expect(throws: SwiftalkError.self) { try eval("var s = Set()\ns.insert({ $0 })") }
        #expect(throws: SwiftalkError.self) { try eval("var a = []\nvar b: [Int] = a") }   // the binding decided
    }

    @Test("an unbound empty still lands in any typed slot; an empty element adopts its siblings' type")
    func adopts() throws {
        #expect(try eval("var c: [Int] = []\nc.Type.String()") == .string("[Int]"))
        #expect(try eval("struct S { var xs: [Int] }\nS(xs: []).xs.Type.String()") == .string("[Int]"))
        #expect(try eval("var c: [Int] = [1]\nc = []\nc.Type.String()") == .string("[Int]"))
        #expect(try eval("var c: [Int] = Array()\nc.Type.String()") == .string("[Int]"))
        #expect(try eval("[[], [1]].Type.String()") == .string("[[Int]]"))
        #expect(try eval("[[]].Type.String()") == .string("[[SION]]"))
        #expect(try eval("[[:]].Type.String()") == .string("[[SION: SION]]"))
        #expect(try eval("[\"a\": [], \"b\": [1]].Type.String()") == .string("[String: [Int]]"))
        #expect(try eval("var w = [[], [1]]\nw[0].append(2)\nw") == .array([.array([.int(2)]), .array([.int(1)])]))
        #expect(throws: SwiftalkError.self) { try eval("var w = [[], [1]]\nw[0].append(\"x\")") }
    }

    @Test("a SION lock admits a stamped [Int] or [String: Int]; Primitives is gone")
    func admitsRoster() throws {
        #expect(try eval("let xs = [1, 2]\nvar s: [SION] = xs\ns.Type.String()") == .string("[SION]"))
        #expect(try eval("let m = [\"a\": 1]\nvar d: [SION: SION] = m\nd.count") == .int(1))
        #expect(try eval("var a = []\na = [1, 2].map { $0 }\na.count") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("var s: [SION] = [{ $0 }]") }
        #expect(throws: SwiftalkError.self) { try eval("let p: [Primitives] = [1]") }
        #expect(throws: SwiftalkError.self) { try eval("let p: Primitives = 1") }
    }
}
