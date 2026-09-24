import Testing
@testable import Swiftalk

/// Round 164: `Interpreter.complete(text)` — names in scope, keywords,
/// REPL commands, and members after a dot; the builtin member table is
/// checked against the evaluator.
@Suite("completion — names, members, and the builtin table (round 164)")
struct CompletionTests {
    @Test("names in scope: bindings, types, builtins, keywords; the word's start is reported")
    func names() throws {
        let i = try interpreter()
        _ = try i.eval("let alpha = 1\nvar alphabet = 2\nstruct Alpine { var x = 0 }")
        let (start, all) = i.complete("let z = alp")
        #expect(start == 8)
        #expect(all == ["alpha", "alphabet"])
        #expect(i.complete("Alp").candidates == ["Alpine"])
        #expect(i.complete("pri").candidates == ["print"])
        #expect(i.complete("fe").candidates == ["fetch"])
        #expect(i.complete("Res").candidates == ["Response", "Result"])
        #expect(i.complete("whi").candidates == ["while"])
        #expect(i.complete("x = xo").candidates == ["xor"])
        #expect(!i.complete("").candidates.contains { $0.hasPrefix("@") || $0.hasPrefix("$") })
        #expect(i.complete("").candidates.contains("Int") && i.complete("").candidates.contains("let"))
        #expect(i.complete("zzz").candidates.isEmpty)
    }

    @Test("REPL commands at a line's start")
    func commands() throws {
        let i = try interpreter()
        #expect(i.complete(":").candidates == [":d", ":h", ":r"])
        #expect(i.complete("  :r").candidates == [":r"])
        #expect(i.complete(":").start == 0)
        #expect(i.complete("x :").candidates.isEmpty)
    }

    @Test("members after a dot: struct properties and methods, enum cases, type statics, Result, extensions, a leading dot")
    func members() throws {
        let i = try interpreter()
        _ = try i.eval("""
            struct P { var x = 0; var y = 0; var norm { .x * .x + .y * .y }; let moved = { self }; static let origin = Self(); static var unit { Self(x: 1) } }
            enum Shape { case circle(Double), dot; let area = { 0.0 } }
            let p = P()
            let s = Shape.dot
            extension Int { let twice = { self * 2 }; var half { self / 2 }; static let answer = 42 }
            """)
        #expect(i.complete("p.").candidates == ["String", "Type", "debugDescription", "description", "moved", "norm", "x", "y"])
        #expect(i.complete("p.n").candidates == ["norm"])
        #expect(i.complete("print(p.m").candidates == ["moved"])
        #expect(i.complete("print(p.m").start == 8)
        #expect(i.complete("P.").candidates == ["String", "Type", "conforms", "name", "origin", "unit"])
        #expect(i.complete("Shape.").candidates == ["String", "Type", "circle", "conforms", "dot", "name"])
        #expect(i.complete("s.").candidates == ["String", "Type", "area", "circle", "debugDescription", "description", "dot"])
        #expect(i.complete("P.origin.").candidates.contains("norm"))                    // a chain of names
        #expect(i.complete("42.").candidates.contains("twice") && i.complete("42.").candidates.contains("half"))
        #expect(i.complete("Int.a").candidates == ["answer"])
        #expect(i.complete("Int.m").candidates == ["max", "min"])
        #expect(i.complete("Double.sq").candidates == ["sqrt", "sqrt2", "sqrtHalf"])
        #expect(i.complete("eval(\"1\").").candidates.isEmpty)                         // a call is never evaluated for completion
        #expect(i.complete("nosuch.").candidates.isEmpty)
        #expect(i.complete(".succ").candidates == ["success"])
        #expect(i.complete("x.String(.pr").candidates == ["pretty", "propertyList"])
        #expect(i.complete("x.String(.pre").candidates == ["pretty"])
        #expect(i.complete("[1, 2].ma").candidates == ["map", "max"])
        #expect(i.complete("\"s\".").candidates.contains("normalized"))
        #expect(i.complete("(await fetch(\"u\")).").candidates.isEmpty)
        #expect(i.complete("Response().").candidates.isEmpty)                          // a call: never evaluated
        _ = try i.eval("let r = Response()")
        #expect(i.complete("r.").candidates.contains("json") && i.complete("r.o").candidates == ["ok"])
    }

    @Test("the builtin member table names members the evaluator knows")
    func table() throws {
        let samples: [String: String] = [
            "Nil": "nil", "Bool": "true", "Int": "1", "Double": "1.5", "String": "\"a\"", "Array": "[1]",
            "Dictionary": "[\"a\": 1]", "Set": "Set(1)", "Range": "1...2", "Function": "{ 1 }",
            "Sequence": "Sequence { yield 1 }", "Data": "Data(\"AQID\")", "Date": ".Date(0.0)", "Task": "async { 1 }",
            "Tuple": "(1, 2)", "Regex": "/a/", "Byte": "Byte(1)", "Result": ".success(1)",
        ]
        for (type, names) in Completion.members {
            let sample = try #require(samples[type], "no sample for \(type)")
            for name in names + Completion.common {
                let i = try interpreter()
                let uncalled = (try? i.eval("(\(sample)).\(name)")) != nil || !isUnknown { try i.eval("(\(sample)).\(name)") }
                let called = (try? i.eval("(\(sample)).\(name)()")) != nil || !isUnknown { try i.eval("(\(sample)).\(name)()") }
                #expect(uncalled || called, "\(type).\(name) is not a member the evaluator knows")
            }
        }
        for (type, names) in Completion.statics {
            for name in names {
                let i = try interpreter()
                let uncalled = (try? i.eval("\(type).\(name)")) != nil || !isUnknown { try i.eval("\(type).\(name)") }
                let called = (try? i.eval("\(type).\(name)(1.0)")) != nil || !isUnknown { try i.eval("\(type).\(name)(1.0)") }
                #expect(uncalled || called, "\(type).\(name) is not a static the evaluator knows")
            }
        }
    }

    private func isUnknown(_ body: () throws -> Value) -> Bool {
        do { _ = try body(); return false } catch SwiftalkError.unknownMember { return true } catch { return false }
    }
}
