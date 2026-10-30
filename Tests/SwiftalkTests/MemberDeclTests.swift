import Testing
@testable import Swiftalk

@Suite("let T.m / var T.p / static let T.s — members one at a time (round 228)")
struct MemberDeclTests {
    @Test("a builtin takes a method, a computed property, a static, and a static getter without an extension body")
    func builtin() throws {
        #expect(try eval("let Int.doubled = { self * 2 }\n21.doubled()") == .int(42))
        #expect(try eval("var Int.squared { self * self }\n12.squared") == .int(144))
        #expect(try eval("var Int.half: Int { self / 2 }\n9.half") == .int(4))
        #expect(try eval("static let Int.answer = 42\nInt.answer") == .int(42))
        #expect(try eval("static var Int.two { 2 }\nInt.two") == .int(2))
        #expect(try eval("static let Int.plus = { a, b in a + b }\nInt.plus(1, 2)") == .int(3))
        #expect(try eval("let Int.m = { 1 }\n5.m()") == .int(1))                            // the echo of a declaration is nothing
    }

    @Test("a struct: Self and implicit self inside, a setter writes back, and the type's statics")
    func structMembers() throws {
        #expect(try eval("""
            struct P { var x: Int = 0 }
            var P.twice { get { .x * 2 } set { .x = newValue / 2 } }
            var p = P(x: 3)
            p.twice = 10
            p.x
            """) == .int(5))
        #expect(try eval("""
            struct P { var x: Int = 0 }
            let P.next = { Self(x: .x + 1) }
            static let P.origin = Self(x: 0)
            [P(x: 3).next().x, P.origin.x]
            """) == .array([.int(4), .int(0)]))
        #expect(try eval("""
            struct P { var x: Int = 0 }
            static var P.unit { Self(x: 1) }
            P.unit.x
            """) == .int(1))
    }

    @Test("an enum takes methods and statics, no computed property — an extension's rule")
    func enumMembers() throws {
        #expect(try eval("enum E { case a, b }\nlet E.name = { \"e\" }\nE.a.name()") == .string("e"))
        #expect(try eval("enum E { case a, b }\nstatic let E.count = 2\nE.count") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("enum E { case a, b }\nvar E.n { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("enum E { case a, b }\nstatic let E.a = 1") }   // a case's name
    }

    @Test("the rules are an extension's: no overwriting, stored properties and unknown types refused")
    func extensionRules() throws {
        #expect(throws: SwiftalkError.self) { try eval("let Int.m = { 1 }\nlet Int.m = { 2 }") }
        #expect(throws: SwiftalkError.self) { try eval("struct Q { var x: Int = 1 }\nvar Q.x { 2 }") }
        #expect(throws: SwiftalkError.self) { try eval("struct Q { var x: Int = 1 }\nlet Q.m = { 1 }\nlet Q.m = { 2 }") }
        #expect(throws: SwiftalkError.self) { try eval("let Nope.m = { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("let x = 1\nlet x.m = { 1 }") }             // a value is not a type
        // a declaration elsewhere is untouched: the dot decides
        #expect(try eval("let x = 1\nx") == .int(1))
        #expect(try eval("let static = 1\nstatic + 1") == .int(2))                           // `static` stays a word
    }

    @Test("the shapes refused, and what the messages say")
    func syntax() throws {
        #expect(throws: SwiftalkError.self) { try eval("let Int.x = 1") }                         // a method is a closure
        #expect(throws: SwiftalkError.self) { try eval("var Int.x = 1") }                         // a computed property has a body
        #expect(throws: SwiftalkError.self) { try eval("let a.b.c = { 1 }") }                     // one dot
        #expect(throws: SwiftalkError.self) { try eval("static let x = 1") }                      // no type named
        #expect(throws: SwiftalkError.self) { try eval("static var Int.v { get { 1 } set { } }") } // no static setter
        #expect(throws: SwiftalkError.self) { try eval("export let Int.m = { 1 }") }              // nothing to export
        #expect(throws: SwiftalkError.self) { try eval("let Int.$x = { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("let Int. = { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("static let Int.k") }
        #expect(throws: SwiftalkError.self) { try eval("let Int.w: Int = { 1 }") }               // a method takes no annotation
        let messages: [(String, String)] = [
            ("let Int.x = 1", "let Int.x = { ... } adds a method — a closure; var Int.x { ... } a computed property"),
            ("let a.b.c = { 1 }", "let Type.name takes one dot — 'a.b' is not a type name"),
            ("static let x = 1", "'static' belongs in a type body — or names the type: static let Type.x ..."),
            ("let Nope.m = { 1 }", "unknown type 'Nope'"),
        ]
        for (source, expected) in messages {
            #expect(throws: SwiftalkError.self) {
                do { try eval(source) } catch let e as SwiftalkError {
                    #expect(e.description.contains(expected), "\(source): \(e.description)")
                    throw e
                }
            }
        }
    }
}
