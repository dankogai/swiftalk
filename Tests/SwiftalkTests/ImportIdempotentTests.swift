import Testing
@testable import Swiftalk

// Round 202: `import` is idempotent — a name already bound to the very
// value the module exports (by the prelude, or by an earlier import) is
// skipped, so a script says `import from "BigInt"` and runs with or
// without the prelude. A name bound to anything else is still an error.

@Suite("import is idempotent (round 202)")
struct ImportIdempotentTests {
    let m = """
        export let twice = { x in x * 2 }
        export let name = "m"
        """

    @Test("importing what the prelude already brought is a no-op, so a script can say what it needs")
    func prelude() throws {
        let i = try interpreter(relaxed: true)                          // the prelude: BigInt, IO, ... are builtins
        #expect(try i.eval("import from \"BigInt\"\n2n ** 70n") == (try i.eval("1180591620717411303424n")))
        #expect(try i.eval("import (BigInt) from \"BigInt\"\nBigInt(3) == 3n") == .bool(true))
        #expect(try i.eval("import (print, debugPrint) from \"IO\"\nprint.Type == Function") == .bool(true))
        #expect(try i.eval("import from \"IO\"\nimport from \"Net\"\nimport from \"Regex\"\n/a/.pattern") == .string("a"))
        // ...and without the prelude the same lines bring the module
        let bare = Swiftalk.Interpreter()
        bare.modulePath = [buildDirectory()].compactMap { $0 }
        #expect(try bare.eval("import from \"BigInt\"\n2n ** 70n") == (try i.eval("2n ** 70n")))
    }

    @Test("the same module imported twice, by name or namespace; a second namespace is an alias")
    func twice() throws {
        let i = try interpreter(relaxed: true)
        i.moduleLoader = { [m] spec in
            guard spec == "m.swt" else { throw SwiftalkError.type("no module '\(spec)'") }
            return m
        }
        #expect(try i.eval("import (twice) from \"./m.swt\"\ntwice(1)") == .int(2))
        #expect(try i.eval("import (twice) from \"./m.swt\"\ntwice(2)") == .int(4))      // again: not "redeclaration of 'twice'"
        #expect(try i.eval("import from \"./m.swt\"\nname") == .string("m"))            // the plain form over both, one already bound
        #expect(try i.eval("import M from \"./m.swt\"\nM.name") == .string("m"))
        #expect(try i.eval("import M from \"./m.swt\"\nM.twice(3)") == .int(6))          // the namespace again
        #expect(try i.eval("import N from \"./m.swt\"\nN == M") == .bool(true))           // an alias (round 184)
    }

    @Test("a name bound to something else is still the redeclaration error")
    func conflict() throws {
        let i = try interpreter(relaxed: true)
        i.moduleLoader = { [m] spec in
            guard spec == "m.swt" else { throw SwiftalkError.type("no module '\(spec)'") }
            return m
        }
        _ = try i.eval("let twice = 2")
        #expect(throws: SwiftalkError.self) { try i.eval("import (twice) from \"./m.swt\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("import from \"./m.swt\"") }
        #expect(try i.eval("twice") == .int(2))                                            // untouched
        // the Complex trap stays (round 191): with the prelude, `IO` is the type, not a namespace to bind
        #expect(throws: SwiftalkError.self) { try i.eval("import IO from \"IO\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("let print = 1") }                // a builtin, as ever
    }
}
