import Testing
@testable import Swiftalk

// Round 185: the top level keeps only `eval`. print/debugPrint live in
// the IO module, fetch/Response in Net, zip is Sequence.zip, sleep is
// Task.sleep; the CLI preimports IO and Net as its prelude.
struct PreludeTests {
    @Test("a bare Interpreter has no print, fetch, zip, or sleep at the top level — only eval")
    func bare() throws {
        let i = Swiftalk.Interpreter()
        #expect(throws: SwiftalkError.self) { try i.eval("print(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("debugPrint(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("fetch(\"https://x/\")") }
        #expect(throws: SwiftalkError.self) { try i.eval("Response()") }
        #expect(throws: SwiftalkError.self) { try i.eval("zip([1], [2])") }
        #expect(throws: SwiftalkError.self) { try i.eval("sleep(0)") }
        #expect(try i.eval("eval(\"1 + 1\")!") == .int(2))
        #expect(throws: SwiftalkError.self) { try Swiftalk.eval("print(1)") }          // the one-liner is bare too
    }

    @Test("import from \"IO\" brings print and debugPrint; import IO from \"IO\" is IO.print; Net has fetch and Response")
    func modules() throws {
        let dir = try #require(buildDirectory())
        let i = Swiftalk.Interpreter()
        i.modulePath = [dir]
        var out = ""
        i.output = { out += $0 }
        i.errorOutput = { out += $0 }
        _ = try i.eval("import from \"IO\"\nprint(1, \"a\")\ndebugPrint(\"a\")")
        #expect(out == "1 a\n\"a\"\n")
        let j = Swiftalk.Interpreter()
        j.modulePath = [dir]
        out = ""
        j.output = { out += $0 }
        _ = try j.eval("import IO from \"IO\"\nIO.print(\"x\")")
        #expect(out == "x\n")
        #expect(throws: SwiftalkError.self) { try j.eval("print(1)") }                  // only the namespace was bound
        let k = Swiftalk.Interpreter()
        k.modulePath = [dir]
        #expect(try k.eval("import Net from \"Net\"\nNet.fetch.Type == Function") == .bool(true))
        #expect(try k.eval("Net.Response(status: 204).ok") == .bool(true))
        k.hooks["fetch"] = { _ in throw Swiftalk.Error.type("no network here") }
        #expect(try k.eval("(await Net.fetch(\"https://x/\")).failure.contains(\"no network\")") == .bool(true))
        #expect(try k.eval("extension Net { static let resolve = { host in host } }\nNet.resolve(\"h\")") == .string("h"))
    }

    @Test("Sequence.zip and Task.sleep are statics of core types")
    func statics() throws {
        #expect(try eval("Sequence.zip([1, 2], \"ab\")") == .array([.tuple([.int(1), .string("a")], labels: [nil, nil]), .tuple([.int(2), .string("b")], labels: [nil, nil])]))
        #expect(try eval("Sequence.zip(1..., \"ab\").Type == Sequence") == .bool(true))
        #expect(try eval("Sequence.zip([], []).Type.String()") == .string("[Tuple]"))
        #expect(try eval("let z = Sequence.zip\nz([1], [2]).count") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("Sequence.zip([1])") }
        #expect(throws: SwiftalkError.self) { try eval("Sequence.zip(a: [1], b: [2])") }
        #expect(try eval("Task.sleep(0)") == .nil)
        #expect(try eval("Task.sleep(0.0)") == .nil)
        #expect(try eval("Task.sleep.Type == Function") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("Task.sleep(-1)") }
        #expect(throws: SwiftalkError.self) { try eval("Task.sleep(\"1\")") }
    }

    @Test("preimport: IO and Net by default, into the builtins — a module sees print, a redeclaration is refused, twice is harmless")
    func preimport() throws {
        let dir = try #require(buildDirectory())
        let i = Swiftalk.Interpreter()
        i.modulePath = [dir]
        try i.preimport()
        try i.preimport()                                                              // idempotent
        var out = ""
        i.output = { out += $0 }
        i.moduleLoader = { _ in "export let say = { print(\"from a module\") }" }
        _ = try i.eval("import (say) from \"./m.swt\"\nsay()")
        #expect(out == "from a module\n")
        #expect(try i.eval("Response(status: 200).ok") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("let print = 1") }            // a builtin, as ever
        #expect(throws: SwiftalkError.self) { try i.eval("import from \"IO\"") }       // print is already bound
        let j = Swiftalk.Interpreter()
        j.modulePath = [dir]
        try j.preimport(["IO"])
        #expect(throws: SwiftalkError.self) { try j.eval("fetch(\"https://x/\")") }
        #expect(throws: SwiftalkError.self) { try j.preimport(["Nowhere"]) }
        let other = Swiftalk.Module(name: "Other")
        other.function("print") { _ in .nil }
        try j.register(other)
        #expect(throws: SwiftalkError.self) { try j.preimport(["Other"]) }             // print is bound to IO's
    }
}
