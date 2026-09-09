import Testing
@testable import Swiftalk

@Suite("Set — unordered, unique, Hashable elements (round 132)")
struct SetTests {
    @Test("construction from any finite Sequence; equality ignores order; the source form is Set([...]) sorted, and re-enters")
    func construction() throws {
        #expect(try eval("Set([3, 1, 2, 1])") == .set([.int(1), .int(2), .int(3)]))
        #expect(try eval("Set([3, 1, 2]) == Set([1, 2, 3])") == .bool(true))
        #expect(try eval("Set()") == .set([]))
        #expect(try eval("Set().count") == .int(0))
        #expect(try eval("Set(1...3) == Set([1, 2, 3])") == .bool(true))
        #expect(try eval("Set(\"hello\").count") == .int(4))
        #expect(try eval("Set([\"a\": 1]) == Set([(\"a\", 1)])") == .bool(true))            // a Dictionary's pairs
        #expect(try eval("Set(Set([1])) == Set([1])") == .bool(true))
        #expect(try eval("[1, 1, 2].Set().count") == .int(2))                                // the conversion law
        #expect(try eval("Set([2, 1]).String()") == .string("Set([1, 2])"))
        #expect(try eval("Set([\"b\", \"a\"]).String()") == .string("Set([\"a\", \"b\"])"))
        #expect(try eval("Set().String()") == .string("Set()"))
        #expect(try eval("let s = Set([3, 1, 2])\neval(s.String()) == s") == .bool(true))      // the round-trip law
        #expect(try eval("Set([1, 2]).debugDescription") == .string("Set([+0x1, +0x2])"))
        #expect(try eval("Set([[1, 2], [3]]).String(.pretty)") == .string("Set([\n  [\n    1,\n    2\n  ],\n  [\n    3\n  ]\n])"))
        #expect(try eval("Set([1]).Type == Set") == .bool(true))
        #expect(try eval("Set([1]).Type.name") == .string("Set"))
        #expect(try eval("Set.conforms(to: Sequence)") == .bool(true))
        #expect(try eval("Set.conforms(to: Hashable)") == .bool(true))
        #expect(try eval("[Set([1]): \"one\"][Set([1])]") == .string("one"))              // a Set is a key
        #expect(throws: SwiftalkError.self) { try eval("Set(0...)") }                        // finite only
        #expect(try eval("Set(1)") == .set([.int(1)]))                                        // one non-Sequence argument: the singleton (round 133)
        #expect(try eval("Set(Set(1))") == .set([.int(1)]))
        #expect(try eval("Set([1]) == Set(1)") == .bool(true))
    }

    @Test("members: count, contains, insert, remove, iteration, map → Array, filter → Set, sorted → Array")
    func members() throws {
        let s = "var s = Set([1, 2, 3])\n"
        #expect(try eval(s + "s.count") == .int(3))
        #expect(try eval(s + "s.contains(2)") == .bool(true))
        #expect(try eval(s + "s.contains(5)") == .bool(false))
        #expect(try eval(s + "s.contains { $0 > 2 }") == .bool(true))
        #expect(try eval(s + "s.insert(4)") == .bool(true))
        #expect(try eval(s + "s.insert(1)") == .bool(false))
        #expect(try eval(s + "s.insert(4)\ns.count") == .int(4))
        #expect(try eval(s + "s.remove(2)") == .int(2))
        #expect(try eval(s + "s.remove(9)") == .nil)
        #expect(try eval(s + "s.remove(2)\ns == Set([1, 3])") == .bool(true))
        #expect(try eval(s + "var n = 0\nfor x in s { n = n + x }\nn") == .int(6))
        #expect(try eval(s + "s.map { $0 * 10 }.sorted()") == .array([.int(10), .int(20), .int(30)]))
        #expect(try eval(s + "s.filter { $0 != 2 }") == .set([.int(1), .int(3)]))
        #expect(try eval(s + "s.filter { $0 != 2 }.Type == Set") == .bool(true))
        #expect(try eval(s + "s.sorted()") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval(s + "s.sorted { $0 > $1 }") == .array([.int(3), .int(2), .int(1)]))
        #expect(try eval(s + "s.reduce(0) { $0 + $1 }") == .int(6))
        #expect(try eval(s + "Array(s).sorted()") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval(s + "s.Array().count") == .int(3))
        #expect(try eval(s + "s.enumerated().count") == .int(3))
        #expect(try eval(s + "s.prefix(2).count") == .int(2))                                  // an Array, as a slice of the unordered is
        #expect(throws: SwiftalkError.self) { try eval("let s = Set([1])\ns.insert(2)") }    // a let
        #expect(throws: SwiftalkError.self) { try eval("Set([1]).insert(2)") }                 // a temporary
        #expect(throws: SwiftalkError.self) { try eval("Set([1])[0]") }                        // unordered: no subscript
        #expect(throws: SwiftalkError.self) { try eval("var a = [1]\na.insert(2)") }
    }

    @Test("algebra: union, intersection, subtracting, symmetricDifference, the is* predicates — a Set or any Sequence on the right")
    func algebra() throws {
        let s = "let a = Set([1, 2, 3])\nlet b = Set([3, 4])\n"
        #expect(try eval(s + "a.union(b)") == .set([.int(1), .int(2), .int(3), .int(4)]))
        #expect(try eval(s + "a.intersection(b)") == .set([.int(3)]))
        #expect(try eval(s + "a.subtracting(b)") == .set([.int(1), .int(2)]))
        #expect(try eval(s + "a.symmetricDifference(b)") == .set([.int(1), .int(2), .int(4)]))
        #expect(try eval(s + "a.union([4, 5])") == .set([.int(1), .int(2), .int(3), .int(4), .int(5)]))
        #expect(try eval(s + "a.intersection(2...9)") == .set([.int(2), .int(3)]))
        #expect(try eval(s + "Set([3]).isSubset(of: a)") == .bool(true))
        #expect(try eval(s + "Set([3]).isSubset(a)") == .bool(true))
        #expect(try eval(s + "a.isSubset(of: a) && !a.isStrictSubset(of: a)") == .bool(true))
        #expect(try eval(s + "a.isSuperset(of: [1, 2])") == .bool(true))
        #expect(try eval(s + "a.isStrictSuperset(of: [1, 2])") == .bool(true))
        #expect(try eval(s + "a.isDisjoint(with: b)") == .bool(false))
        #expect(try eval(s + "a.isDisjoint(with: Set([9]))") == .bool(true))
        #expect(try eval(s + "[a, b] == [Set([1, 2, 3]), Set([3, 4])]") == .bool(true))       // operands untouched
        #expect(throws: SwiftalkError.self) { try eval("[1].union([2])") }
        #expect(throws: SwiftalkError.self) { try eval("Set([1]).union(1)") }
        #expect(throws: SwiftalkError.self) { try eval("Set([1]).isSubset(within: Set([1]))") }
    }

    @Test("keys only (round 133): s0 + s1 is union, s0 - s1 subtraction, += and -= follow; merge/delete in place, no function; Set(a, b, ...) lists elements")
    func keysOnly() throws {
        #expect(try eval("Set(\"one\", \"two\") + Set(\"two\", \"three\") == Set(\"one\", \"two\", \"three\")") == .bool(true))
        #expect(try eval("Set(\"one\", \"two\") - Set(\"two\", \"three\") == Set(\"one\")") == .bool(false))      // Set("one") is graphemes: {"o","n","e"}
        #expect(try eval("Set(\"one\", \"two\") - Set(\"two\", \"three\") == Set([\"one\"])") == .bool(true))
        #expect(try eval("Set(1, 2) + Set(2, 3)") == .set([.int(1), .int(2), .int(3)]))
        #expect(try eval("Set(1, 2) - Set(2, 3)") == .set([.int(1)]))
        #expect(try eval("var s = Set(1, 2)\ns += Set(3)\ns -= Set(1)\ns") == .set([.int(2), .int(3)]))
        #expect(try eval("var s = Set(1, 2)\ns.merge(Set(2, 3))\ns") == .set([.int(1), .int(2), .int(3)]))
        #expect(try eval("var s = Set(1, 2)\ns.merge([3, 4])\ns.count") == .int(4))                          // any Sequence
        #expect(try eval("var s = Set(1, 2)\ns.merge(Set(2, 3)) == nil") == .bool(true))
        #expect(try eval("var s = Set(1, 2, 3)\ns.delete(Set(2, 9))\ns") == .set([.int(1), .int(3)]))
        #expect(try eval("var s = Set(1, 2, 3)\ns.delete(1...2)\ns") == .set([.int(3)]))
        #expect(try eval("var d = [\"a\": 1, \"b\": 2, \"c\": 3]\nd.delete(Set(\"a\", \"z\"))\nd.keys") == .set([.string("b"), .string("c")]))
        #expect(try eval("var d = [\"a\": 1, \"b\": 2]\nd.delete([\"b\": 0])\nd") == .dictionary([.string("a"): .int(1)]))
        #expect(try eval("var d = [\"a\": 1, \"b\": 2]\nd.delete([\"a\"])\nd.count") == .int(1))
        #expect(try eval("Set([1]) ?? Set([2])") == .set([.int(1)]))                                        // ?? / !! not special on Sets: the general rule
        #expect(try eval("Set([1]) !! Set([2])") == .set([.int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("let s = Set(1)\ns.merge(Set(2))") }
        #expect(throws: SwiftalkError.self) { try eval("Set(1, 2) + [3]") }                                  // a Set and an Array
        #expect(throws: SwiftalkError.self) { try eval("Set(1, 2) * Set(3)") }
        #expect(throws: SwiftalkError.self) { try eval("var s = Set(1)\ns.merge(Set(2), Set(3))") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1]\na.delete([1])") }
    }

    @Test("type discipline: Set<Int> annotations, inference, locks; JSON writes a sorted array")
    func types() throws {
        #expect(try eval("let s: Set<Int> = Set([1, 2])\ns.count") == .int(2))
        #expect(try eval("var s: Set<String> = Set()\ns.insert(\"a\")\ns") == .set([.string("a")]))
        #expect(throws: SwiftalkError.self) { try eval("var s: Set<Int> = Set()\ns.insert(\"a\")") }
        #expect(throws: SwiftalkError.self) { try eval("let s: Set<Int> = Set([\"a\"])") }
        #expect(throws: SwiftalkError.self) { try eval("var s = Set([1])\ns = Set([\"a\"])") }        // inferred Set<Int>
        #expect(throws: SwiftalkError.self) { try eval("let s = Set([1, \"a\"])") }                     // mixed: annotate
        #expect(try eval("let s: Set<Any> = Set([1, \"a\"])\ns.count") == .int(2))
        #expect(try eval("let s: Set<Int>? = nil\ns == nil") == .bool(true))
        #expect(try eval("let s: Set<Set<Int>> = Set([Set([1])])\ns.count") == .int(1))
        #expect(try eval("var s = Set([1, nil])\ns.insert(nil)\ns.count") == .int(2))                  // Set<Int?>
        #expect(throws: SwiftalkError.self) { try eval("let s: Set<Nope> = Set()") }
        #expect(try eval("Set([2, 1]).String(.json)") == .string("[1,2]"))
        #expect(try eval("[\"s\": Set([\"b\", \"a\"])].String(.json)") == .string("{\"s\":[\"a\",\"b\"]}"))
        #expect(try eval("SION(propertyList: Set([1]).String(.propertyList)) == [1]") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("let v: SION = Set([1])") }                         // not SION: no literal
    }

    @Test("d.keys is a Set (revising round 127): d0.keys == d1.keys whenever d0 == d1; values stays an Array")
    func keys() throws {
        #expect(try eval("[\"a\": 1, \"b\": 2].keys == Set([\"a\", \"b\"])") == .bool(true))
        #expect(try eval("[\"a\": 1, \"b\": 2].keys.Type == Set") == .bool(true))
        #expect(try eval("let d0 = [\"a\": 1, \"b\": 2, \"c\": 3]\nlet d1 = [\"c\": 3, \"b\": 2, \"a\": 1]\nd0 == d1 && d0.keys == d1.keys") == .bool(true))
        #expect(try eval("[\"a\": 1].keys.contains(\"a\")") == .bool(true))
        #expect(try eval("[\"a\": 1, \"b\": 2].keys.sorted()") == .array([.string("a"), .string("b")]))
        #expect(try eval("[\"a\": 1, \"b\": 2].values.Type == Array") == .bool(true))
        #expect(try eval("[\"a\": 1, \"b\": 2].keys.intersection([\"b\", \"z\"])") == .set([.string("b")]))
    }
}
