import Testing
@testable import Swiftalk

// Round 186: a module owns values — `Value.host` — and types; Regex is the
// first, its engine out of the core, the literal's grammar staying.
struct HostValueTests {
    /// An in-process module with a type of its own: Money(cents).
    final class Money: Swiftalk.HostValue {
        let cents: Int64
        let type: Swiftalk.Value
        init(_ cents: Int64, type: Swiftalk.Value) { self.cents = cents; self.type = type }
        var typeName: String { "Money" }
        func member(_ name: String, args: [Swiftalk.Value], called: Bool) throws -> Swiftalk.Value? {
            switch (name, called) {
            case ("cents", false):   return .int(cents)
            case ("doubled", true):  return .host(Money(cents * 2, type: type))
            default:                 return nil
            }
        }
        func isEqual(to other: any Swiftalk.HostValue) -> Bool { (other as? Money)?.cents == cents }
        func hash(into hasher: inout Hasher) { hasher.combine(cents) }
        func sourceString(debug: Bool) -> String { "Money(\(cents))" }
        func patternMatch(_ subject: Swiftalk.Value, binding: Bool) throws -> Swiftalk.Value? {
            guard case .int(let i) = subject else { return nil }
            return i >= cents ? .int(i - cents) : nil          // "at least this much": the change
        }
    }

    private func interpreter() throws -> Swiftalk.Interpreter {
        let i = Swiftalk.Interpreter()
        let m = Swiftalk.Module(name: "Bank")
        final class Box { var type: Swiftalk.Value = .nil }
        let box = Box()
        box.type = m.type("Money") { args in
            guard args.count == 1, case .int(let c) = args[0] else { throw Swiftalk.Error.type("Money(cents) takes an Int") }
            return .host(Money(c, type: box.type))
        }
        m.extend("Int", "money") { receiver, args, called in
            guard called, args.isEmpty, case .int(let c) = receiver else { return nil }
            return .host(Money(c, type: box.type))
        }
        m.extend("String", "count") { receiver, args, called in
            guard !called, case .string(let s) = receiver, s == "money" else { return nil }   // declines every other String
            return .int(-1)
        }
        i.register(m)
        _ = try i.eval("import from \"Bank\"")
        return i
    }

    @Test("a module's type constructs, answers .Type, prints its own form, compares and hashes as it says; unknown members fall to the core's")
    func hostValue() throws {
        let i = try interpreter()
        #expect(try i.eval("Money(150).cents") == .int(150))
        #expect(try i.eval("Money(150).Type == Money") == .bool(true))
        #expect(try i.eval("Money(150).Type.name") == .string("Money"))
        #expect(try i.eval("Money(150).String()") == .string("Money(150)"))
        #expect(try i.eval("Money(150) == Money(150) && Money(150) != Money(151)") == .bool(true))
        #expect(try i.eval("[Money(1): \"one\"][Money(1)]") == .string("one"))
        #expect(try i.eval("Money(2).doubled().cents") == .int(4))
        #expect(try i.eval("150.Money().cents") == .int(150))                        // round 47's law
        #expect(try i.eval("let m: Money = Money(1)\nm.cents") == .int(1))            // an annotation
        #expect(throws: SwiftalkError.self) { try i.eval("let m: Money = 1") }
        #expect(throws: SwiftalkError.self) { try i.eval("Money(150).nope") }
        #expect(throws: SwiftalkError.self) { try i.eval("Money(\"x\")") }
        #expect(try i.eval("Money(3).Type.Type == Function") == .bool(true))
    }

    @Test("a module extends core types: a new member, and a declining one that leaves the core's answer alone")
    func extensions() throws {
        let i = try interpreter()
        #expect(try i.eval("5.money().cents") == .int(5))
        #expect(try i.eval("\"money\".count") == .int(-1))                          // the module's answer
        #expect(try i.eval("\"other\".count") == .int(5))                            // declined: the core's
        #expect(throws: SwiftalkError.self) { try i.eval("5.money(1)") }              // declined: no such core member
    }

    @Test("switch: a host value is a pattern (~=) and a case binding's source, as its object decides")
    func patterns() throws {
        let i = try interpreter()
        #expect(try i.eval("switch 200 { case Money(150): \"enough\"; default: \"short\" }") == .string("enough"))
        #expect(try i.eval("switch 100 { case Money(150): \"enough\"; default: \"short\" }") == .string("short"))
        #expect(try i.eval("switch \"x\" { case Money(1): \"?\"; default: \"no match, no error\" }") == .string("no match, no error"))
        #expect(try i.eval("switch 200 { case let change = Money(150): change; default: -1 }") == .int(50))
    }

    @Test("without the Regex module the literal is an error naming it, and Regex is undefined; with it, all is as before")
    func regexModule() throws {
        let bare = Swiftalk.Interpreter()
        do {
            _ = try bare.eval("/a+/")
            Issue.record("a regex literal evaluated without the module")
        } catch let error as SwiftalkError {
            #expect(error.description.contains("Regex module"))
        }
        #expect(throws: SwiftalkError.self) { try bare.eval("Regex(\"a\")") }
        #expect(try bare.eval("\"a/b\".split(\"/\")") == .array([.string("a"), .string("b")]))          // the core's split
        #expect(try bare.eval("\"abc\".replacing(\"b\", \"x\")") == .string("axc"))                    // the core's replacing
        #expect(try bare.eval("let f = { /a/ }\n1") == .int(1))                                        // parsed fine, not evaluated
        #expect(throws: SwiftalkError.self) { try bare.eval("\"abc\".firstMatch(\"b\")") }              // no such member without the module
        #expect(try eval("/a+/i.Type == Regex") == .bool(true))
        #expect(try eval("/a+/i.flags") == .string("i"))
        #expect(try eval("\"aaa\".wholeMatch(/a+/) != nil") == .bool(true))
        #expect(try eval("[/a/: 1][/a/]") == .int(1))
        #expect(try eval("\"x\".Regex(\"i\") == /x/i") == .bool(true))
        #expect(try eval("let r: Regex = /x/\nr.pattern") == .string("x"))
        #expect(try eval("\"a,b\".split(/,/).Type.String()") == .string("[String]"))
        #expect(try eval("\"abc\".replacing(\"b\", \"x\")") == .string("axc"))                          // still the core's
        #expect(throws: SwiftalkError.self) { try eval("/a/x/") }
        #expect(throws: SwiftalkError.self) { try eval("Regex(\"(\")") }                                // a bad pattern
        #expect(throws: SwiftalkError.self) { try eval("Regex(\"a\", \"q\")") }                          // a bad flag
        let dir = try #require(buildDirectory())
        let j = Swiftalk.Interpreter()
        j.modulePath = [dir]
        #expect(try j.eval("import (Regex) from \"Regex\"\n/ab/.pattern") == .string("ab"))          // by name, no prelude
    }
}
