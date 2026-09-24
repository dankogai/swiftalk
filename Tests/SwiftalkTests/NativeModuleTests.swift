import Testing
@testable import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Round 182: native modules — Swift exports imported by a bare name,
// registered in-process or loaded from `lib<name>.dylib` on the module
// path; the core is a dynamic library so both sides share one Value.
struct NativeModuleTests {
    private func greet() -> Swiftalk.Module {
        let m = Swiftalk.Module(name: "greet")
        m.function("hello") { args in
            guard case .string(let who)? = args.first else {
                throw Swiftalk.Error.type("hello(name) takes a String")
            }
            return .string("hello, \(who)")
        }
        m.export("answer", .int(42))
        m.export("answer", .int(41))                   // a re-export replaces
        return m
    }

    @Test("a registered module imports by its bare name: every export, a namespace, the named few; a constant reads, a Function calls, its error is the caller's")
    func registered() throws {
        let a = Swiftalk.Interpreter()
        a.register(greet())
        #expect(try a.eval("import from \"greet\"\nhello(\"world\")") == .string("hello, world"))
        #expect(try a.eval("answer") == .int(41))
        #expect(try a.eval("hello.Type.String()") == .string("Function"))
        let b = Swiftalk.Interpreter()
        b.register(greet())
        #expect(try b.eval("import G from \"greet\"\nG.hello(\"x\")") == .string("hello, x"))
        #expect(try b.eval("G.answer") == .int(41))
        let c = Swiftalk.Interpreter()
        c.register(greet())
        #expect(try c.eval("import (answer) from \"greet\"\nanswer") == .int(41))
        #expect(throws: SwiftalkError.self) { try c.eval("import (nope) from \"greet\"") }
        #expect(throws: SwiftalkError.self) { try c.eval("hello") }          // not imported by (answer)
        let d = Swiftalk.Interpreter()
        d.register(greet())
        #expect(throws: SwiftalkError.self) { try d.eval("import from \"greet\"\nhello(1)") }
    }

    @Test("a bare name nobody registered is an error that says where it looked; a path or a .swt is a file as ever")
    func unresolved() throws {
        #expect(throws: SwiftalkError.self) { try Swiftalk.Interpreter().eval("import from \"nowhere\"") }
        do {
            let i = Swiftalk.Interpreter()
            i.modulePath = ["/nonexistent"]
            try i.eval("import from \"nowhere\"")
            Issue.record("imported nothing")
        } catch let error as SwiftalkError {
            #expect(error.description.contains("/nonexistent"))
            #expect(error.description.contains("./nowhere.swt"))
        }
        #expect(ModuleSystem.isBare("env"))
        #expect(!ModuleSystem.isBare("./env"))
        #expect(!ModuleSystem.isBare("env.swt"))
        #expect(!ModuleSystem.isBare("https://x/env"))
        #expect(!ModuleSystem.isBare("libenv" + Swiftalk.Module.librarySuffix))
    }

    @Test("the example module loads from the module path as libenv: get, set, unset, all, platform; and by its path")
    func dynamic() throws {
        let dir = try #require(buildDirectory(), "no lib\("env")\(Swiftalk.Module.librarySuffix) beside the test — build it: swift build")
        let i = Swiftalk.Interpreter()
        i.modulePath = ["/nonexistent", dir]
        #expect(try i.eval("import from \"env\"\nset(\"SWIFTALK_TEST\", \"one\")\nget(\"SWIFTALK_TEST\")") == .string("one"))
        #expect(try i.eval("unset(\"SWIFTALK_TEST\")\nget(\"SWIFTALK_TEST\")") == .nil)
        #expect(try i.eval("all().Type.String()") == .string("[String: String]"))
        #expect(try i.eval("all()[\"PATH\"] == get(\"PATH\")") == .bool(true))
        #expect(try i.eval("platform") == .string(platform))
        #expect(throws: SwiftalkError.self) { try i.eval("get(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("set(\"A\")") }
        let j = Swiftalk.Interpreter()
        let path = dir + "/" + Swiftalk.Module.fileName(for: "env")
        #expect(try j.eval("import env from \"\(path)\"\nenv.platform") == .string(platform))
        #expect(throws: SwiftalkError.self) { try Swiftalk.Interpreter().eval("import from \"env\"") }   // an empty module path
        #expect(throws: SwiftalkError.self) { try Swiftalk.Module.load(path: "/nonexistent" + Swiftalk.Module.librarySuffix) }
    }

    private var platform: String {
        #if os(macOS)
        "darwin"
        #else
        "linux"
        #endif
    }

    /// The build directory: where libSwiftalk lives — dladdr on its
    /// metadata on Darwin, /proc/self/maps on Linux — or a parent of
    /// it; libenv is built beside it.
    private func buildDirectory() -> String? {
        guard let library = libraryPath() else { return nil }
        var dir = ModuleSystem.directory(of: library)
        let file = Swiftalk.Module.fileName(for: "env")
        for _ in 0..<4 {
            if access(dir + "/" + file, R_OK) == 0 { return dir }
            dir = ModuleSystem.directory(of: dir)
        }
        return nil
    }

    private func libraryPath() -> String? {
        #if canImport(Darwin)
        var info = Dl_info()
        let anchor = unsafeBitCast(Swiftalk.Interpreter.self, to: UnsafeRawPointer.self)
        guard dladdr(anchor, &info) != 0, let name = info.dli_fname else { return nil }
        return String(cString: name)
        #else
        guard let maps = try? ModuleSystem.readFile("/proc/self/maps") else { return nil }
        for line in maps.split(separator: "\n") {
            guard line.hasSuffix("/libSwiftalk.so"), let slash = line.firstIndex(of: "/") else { continue }
            return String(line[slash...])
        }
        return nil
        #endif
    }
}
