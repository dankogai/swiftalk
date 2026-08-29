import Testing
@testable import Swiftalk

@Suite("print() and debugPrint() — the first built-in Function values")
struct PrintTests {
    private func capture(_ source: String) throws -> (result: Value, output: String) {
        let interp = Interpreter()
        var out = ""
        interp.output = { out += $0 }
        let result = try interp.eval(source)
        return (result, out)
    }

    @Test("print: raw display — Strings bare, others in source form; space-separated, newline-terminated")
    func printBasics() throws {
        #expect(try capture(#"print("hello, world")"#).output == "hello, world\n")
        #expect(try capture(#"print(1, "two", [3, "x"], nil)"#).output == "1 two [3, \"x\"] nil\n")
        #expect(try capture("print()").output == "\n")
        #expect(try capture("print(0.1 + 0.2)").output == "0.30000000000000004\n")
        #expect(try capture(#"print("\(1 + 1)")"#).output == "2\n")   // same rule as interpolation
    }

    @Test("debugPrint: source form for everything — quoted, round-trippable")
    func debugPrintBasics() throws {
        #expect(try capture(#"debugPrint("hello")"#).output == "\"hello\"\n")
        #expect(try capture(#"debugPrint("a", 1)"#).output == "\"a\" 1\n")
        #expect(try capture(#"debugPrint("line\nbreak")"#).output == "\"line\\nbreak\"\n")
    }

    @Test("print returns nil and is an ordinary Function value")
    func printIsAValue() throws {
        #expect(try capture("print(1)").result == .nil)
        #expect(try eval("print.type") == .string("Function"))
        let (_, out) = try capture("let p = print\np(\"via alias\")")
        #expect(out == "via alias\n")
        // usable as an argument like any function
        let (_, out2) = try capture("let twice = { f, x in f(x)\nf(x) }\ntwice(print, 7)")
        #expect(out2 == "7\n7\n")
    }

    @Test("builtins reject labels and resist redeclaration in the global scope")
    func builtinDiscipline() throws {
        #expect(throws: SwiftalkError.self) { try eval("print(x: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("let print = 42") }
        // ...but shadowing in an inner scope is ordinary lexical scoping
        #expect(try capture("let f = { let print = 42\nprint }\nf()").result == .int(42))
    }

    @Test("output goes through the embedder hook, not straight to stdout")
    func outputHook() throws {
        let interp = Interpreter()
        var lines: [String] = []
        interp.output = { lines.append($0) }
        _ = try interp.eval("for i in 1...3 { print(i) }")
        #expect(lines == ["1\n", "2\n", "3\n"])
    }
}
