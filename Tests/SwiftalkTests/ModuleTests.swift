import Testing
@testable import Swiftalk

/// Modules through an in-memory loader: the Interpreter resolves the
/// spec beside the importer and hands the resolved path to the loader.
@Suite("import / export — modules (round 100)")
struct ModuleTests {
    func interpreter(_ files: [String: String]) -> Swiftalk.Interpreter {
        let interp = Swiftalk.Interpreter()
        interp.moduleLoader = { spec in
            guard let source = files[spec] else { throw SwiftalkError.type("no module '\(spec)'") }
            return source
        }
        return interp
    }
    let geometry = """
        export struct Point { var x: Double; var y: Double }
        var calls = 0
        export let area = { w, h in calls = calls + 1; return w * h }
        export let count = { calls }
        export let unit = 1.0
        let secret = "hidden"
        """

    @Test("import M from: every export under M, a labeled tuple — M.x reads, M.f() calls through")
    func namespace() throws {
        let i = interpreter(["geometry.swt": geometry])
        #expect(try i.eval("import G from \"./geometry.swt\"\nG.area(3.0, 4.0)") == .double(12))
        #expect(try i.eval("G.unit") == .double(1))
        #expect(try i.eval("G.Point(x: 1.0, y: 2.0).x") == .double(1))
        #expect(try i.eval("G.Type == Tuple") == .bool(true))
        #expect(try i.eval("G.count()") == .int(1))
        #expect(throws: SwiftalkError.self) { try i.eval("G.secret") }
        #expect(throws: SwiftalkError.self) { try i.eval("G.area = { 0 }") }       // a let
    }

    @Test("import (a, b) from: the named exports, directly; a module loads once per Interpreter")
    func names() throws {
        let i = interpreter(["geometry.swt": geometry])
        #expect(try i.eval("import (area, unit) from \"./geometry.swt\"\narea(2.0, 5.0) + unit") == .double(11))
        #expect(try i.eval("import G from \"./geometry.swt\"\nG.count()") == .int(1))   // the same instance
        #expect(throws: SwiftalkError.self) { try i.eval("import (secret) from \"./geometry.swt\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("import (area) from \"./geometry.swt\"") }   // redeclaration
    }

    @Test("a module's scope: the builtins, never the importer's globals; export forms; only the top level")
    func scoping() throws {
        let i = interpreter([
            "m.swt": "export let seesPrint = print != nil\nexport let x = 1\nexport (x)\nlet y = 2\nexport (y)\nexport var v = 3\nexport enum E { case a }\nexport let (p, q) = (7, 8)",
            "leaky.swt": "export let peek = { outer }",
        ])
        _ = try i.eval("let outer = 42")
        #expect(try i.eval("import M from \"./m.swt\"\nM") ==
                .tuple([.bool(true), .int(1), .int(2), .int(3), try i.eval("M.E"), .int(7), .int(8)],
                       labels: ["seesPrint", "x", "y", "v", "E", "p", "q"]))
        #expect(try i.eval("M.E.a.Type == M.E") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("import L from \"./leaky.swt\"\nL.peek()") }
        #expect(throws: SwiftalkError.self) { try i.eval("let f = { import Z from \"./m.swt\" }\nf()") }
        #expect(throws: SwiftalkError.self) { try i.eval("let g = { export let z = 1 }\ng()") }
        #expect(throws: SwiftalkError.self) { try i.eval("export (nothing)") }
        #expect(throws: SwiftalkError.self) { try i.eval("export print") }
        #expect(try i.eval("export let top = 1\ntop") == .int(1))               // harmless in a program
    }

    @Test("resolution: beside the importer; ./ and ../ fold; URLs and absolute paths as they are")
    func resolution() throws {
        let i = interpreter([
            "lib/a.swt": "import (b) from \"./sub/b.swt\"\nexport let a = b + 1",
            "lib/sub/b.swt": "import (base) from \"../../base.swt\"\nexport let b = base * 10",
            "base.swt": "export let base = 4",
        ])
        #expect(try i.eval("import (a) from \"./lib/a.swt\"\na") == .int(41))
        #expect(ModuleSystem.resolve("./x.swt", base: ".") == "x.swt")
        #expect(ModuleSystem.resolve("../x.swt", base: "lib/sub") == "lib/x.swt")
        #expect(ModuleSystem.resolve("/abs/x.swt", base: "lib") == "/abs/x.swt")
        #expect(ModuleSystem.resolve("./x.swt", base: "https://h/dir") == "https://h/dir/x.swt")
        #expect(ModuleSystem.resolve("x.swt", base: "/abs/dir") == "/abs/dir/x.swt")
        #expect(ModuleSystem.directory(of: "/abs/dir/x.swt") == "/abs/dir")
        #expect(ModuleSystem.directory(of: "x.swt") == ".")
    }

    @Test("errors: circular imports, a missing module, a module that does not parse, syntax")
    func errors() throws {
        let i = interpreter([
            "a.swt": "import B from \"./b.swt\"\nexport let a = 1",
            "b.swt": "import A from \"./a.swt\"\nexport let b = 2",
            "bad.swt": "export let x = 1 +",
        ])
        #expect(throws: SwiftalkError.self) { try i.eval("import A from \"./a.swt\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("import N from \"./nope.swt\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("import X from \"./bad.swt\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("import M \"./a.swt\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("import {a} from \"./a.swt\"") }
        #expect(throws: SwiftalkError.self) { try i.eval("import M from 42") }
        // a URL without a loader that fetches is refused, not hung
        let plain = Swiftalk.Interpreter()
        #expect(throws: SwiftalkError.self) { try plain.eval("import M from \"https://example.com/m.swt\"") }
    }
}
