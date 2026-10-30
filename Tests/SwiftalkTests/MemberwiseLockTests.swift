import Testing
@testable import Swiftalk

@Suite("the memberwise init's initial-type lock, and a String member's result (round 233)")
struct MemberwiseLockTests {
    @Test("a property without an annotation is locked to its default's type at construction, as on assignment")
    func memberwiseLock() throws {
        #expect(throws: SwiftalkError.self) { try eval("struct P { var y = 0 }\nP(y: \"s\")") }
        #expect(throws: SwiftalkError.self) { try eval("struct P { var y = 0 }\nP(\"s\")") }
        #expect(throws: SwiftalkError.self) { try eval("struct P { var s = \"a\" }\nP(s: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("struct P { var d = 1.5 }\nP(d: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("struct P { var xs = [] }\nP(xs: [:])") }
        #expect(throws: SwiftalkError.self) { try eval("struct P { var y = 0 }\nP(y: nil)") }
        #expect(throws: SwiftalkError.self) { try eval("struct L { let tag = \"pt\"; var x = 0 }\nL(tag: 4)") }
        #expect(try eval("struct P { var y = 0; var s = \"a\"; var xs = [] }\nP(y: 1, s: \"b\", xs: [1, 2]).xs.count") == .int(2))
        #expect(try eval("struct P { var n = nil }\nP(n: \"anything\").n") == .string("anything"))   // a nil default locks nothing
        #expect(try eval("struct P { var o: Int? = nil }\nP(o: 7).o") == .int(7))
        #expect(try eval("struct L { let tag = \"pt\"; var x = 0 }\nL(\"z\", 1).tag") == .string("z"))
        #expect(try eval("struct D { var y = 0; init { v in self.y = v } }\nD(3).y") == .int(3))
    }

    @Test("the message is the assignment's")
    func message() throws {
        do {
            _ = try eval("struct P { var y = 0 }\nP(y: \"s\")")
            Issue.record("expected a type error")
        } catch let error as SwiftalkError {
            #expect("\(error)".contains("cannot assign String to P.y of type Int"))
        }
    }

    @Test("a String member must return a String on every spelling")
    func stringMember() throws {
        #expect(throws: SwiftalkError.self) { try eval("struct B { var n: Int = 0; let String = { 1 } }\nB().String()") }
        #expect(throws: SwiftalkError.self) { try eval("struct B { var n: Int = 0; let String = { 1 } }\nString(B())") }
        #expect(throws: SwiftalkError.self) { try eval("struct B { var n: Int = 0; let String = { 1 } }\nB().String(.pretty)") }
        #expect(throws: SwiftalkError.self) { try eval("struct B { var n: Int = 0; let String = { 1 } }\n\"\\(B())\"") }
        #expect(throws: SwiftalkError.self) { try eval("struct B { var n: Int = 0; let String = { 1 } }\n[B()].String()") }
        #expect(throws: SwiftalkError.self) { try eval("enum E { case a; let String = { 1 } }\nE.a.String()") }
        #expect(try eval("struct G { var n: Int = 0; let String = { \"G\\(.n)\" } }\nG(n: 2).String()") == .string("G2"))
        #expect(try eval("struct G { var n: Int = 0; let String = { \"G\\(.n)\" } }\nString(G(n: 3))") == .string("G3"))
        #expect(try eval("struct G { var n: Int = 0; let Int = { \"not an int\" } }\nG().Int()") == .string("not an int"))   // only String owns a text
    }
}
