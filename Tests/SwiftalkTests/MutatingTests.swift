import Testing
@testable import Swiftalk

@Suite("mutating methods, implicit self, extensions (round 49)")
struct MutatingTests {
    private let stack = """
        struct Stack {
            var value: Array = []
            mutating push = { item in .value.append(item) }
            mutating pop = {
                let last = .value[.value.count - 1]
                .value = .value.prefix(.value.count - 1)
                return last
            }
            let top = { .value.count == 0 ? nil : .value[.value.count - 1] }
        }
        """

    @Test("the marquee: mutating push = { item in .value.append(item) }")
    func marquee() throws {
        #expect(try eval("\(stack)\nvar s = Stack()\ns.push(1)\ns.push(2)\ns.top()") == .int(2))
        #expect(try eval("\(stack)\nvar s = Stack()\ns.push(1)\ns.push(2)\ns.value.count") == .int(2))
        #expect(try eval("\(stack)\nvar s = Stack()\ns.push(9)\nlet got = s.pop()\n[got, s.value.count]")
            == .array([.int(9), .int(0)]))
    }

    @Test("mutating requires a var; COW keeps copies apart")
    func varDiscipline() throws {
        #expect(throws: SwiftalkError.self) { try eval("\(stack)\nlet s = Stack()\ns.push(1)") }
        #expect(try eval("\(stack)\nvar a = Stack()\na.push(1)\nlet b = a\na.push(2)\nb.value.count")
            == .int(1))
    }

    @Test("Array.append: the builtin mutator")
    func arrayAppend() throws {
        #expect(try eval("var a = [1]\na.append(2)\na") == .array([.int(1), .int(2)]))
        #expect(try eval("var a = []\na.append(1, 2, 3)\na.count") == .int(3))
        #expect(try eval("var d = [\"k\": [1]]\nd[\"k\"].append(2)\nd[\"k\"]")
            == .array([.int(1), .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("let a = [1]\na.append(2)") }
        #expect(throws: SwiftalkError.self) { try eval("[1].append(2)") }
    }

    @Test("implicit self: .prop reads, .prop = writes, .method() calls")
    func implicitSelf() throws {
        #expect(try eval("""
            struct P {
                var x: Int = 0
                var y: Int = 0
                let sum = { .x + .y }
                let double = { .sum() * 2 }
                mutating flip = { let t = .x\n.x = .y\n.y = t }
            }
            var p = P(x: 1, y: 5)
            p.flip()
            [p.x, p.y, p.sum(), p.double()]
            """) == .array([.int(5), .int(1), .int(6), .int(12)]))
    }

    @Test("mutating through nested lvalue paths")
    func nestedMutation() throws {
        #expect(try eval("\(stack)\nvar arr = [Stack(), Stack()]\narr[1].push(9)\n[arr[1].value.count, arr[0].value.count]")
            == .array([.int(1), .int(0)]))
    }

    @Test("format members survive implicit-self resolution — unless self shadows them")
    func formatMembersIntact() throws {
        #expect(try eval("""
            struct H { var n: Int = 255\nlet asHex = { .n.String(.hex) } }
            H().asHex()
            """) == .string("0xff"))
        // a self member named like a format member shadows it (documented)
        #expect(throws: SwiftalkError.self) {
            try eval("struct H { var n: Int = 255\nlet hex = { .n.String(.hex) } }\nH().hex()")
        }
    }

    @Test("extensions: methods onto user types and builtins alike (§10)")
    func extensions() throws {
        #expect(try eval("\(stack)\nextension Stack { let depth = { .value.count } }\nvar s = Stack()\ns.push(1)\ns.depth()")
            == .int(1))
        #expect(try eval("extension Int { let doubled = { self * 2 } }\n21.doubled()") == .int(42))
        #expect(try eval("extension Int { let squared = { self * self } }\n3.squared().squared()") == .int(81))
        #expect(try eval("""
            extension Array { mutating pushTwice = { x in .append(x)\n.append(x) } }
            var a = [0]
            a.pushTwice(7)
            a
            """) == .array([.int(0), .int(7), .int(7)]))
        #expect(throws: SwiftalkError.self) { try eval("extension Nowhere { let f = { 1 } }") }
        #expect(throws: SwiftalkError.self) {
            try eval("\(stack)\nextension Stack { let top = { 0 } }")   // duplicate member
        }
    }

    @Test("uncalled mutating methods refuse politely")
    func uncalledMutating() throws {
        #expect(throws: SwiftalkError.self) { try eval("\(stack)\nvar s = Stack()\nlet m = s.push") }
    }
}
