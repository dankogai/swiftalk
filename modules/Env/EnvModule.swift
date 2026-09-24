import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// `Env` — the process environment, swiftalk's first native module
// (round 182) and the worked example of one: a few functions over
// Values, a constant, one C entry point. Built as `libEnv.dylib` (`.so`
// on Linux) beside the CLI, so `import from "Env"` finds it. The
// capital is convention, not grammar (round 183): a module is named
// like a type.
//
//     import (get, set) from "Env"
//     get("HOME")                 // "/Users/me", or nil when unset
//     set("GREETING", "hello")
//     import Env from "Env"
//     Env.all()["GREETING"]       // "hello"
//     Env.platform                // "darwin" or "linux"

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "Env")

    /// `get(name)` — the variable's value, or nil when it is unset.
    m.function("get") { args in
        guard args.count == 1, case .string(let name) = args[0] else {
            throw Swiftalk.Error.type("Env.get(name) takes one String")
        }
        guard let value = getenv(name) else { return .nil }
        return .string(String(cString: value))
    }

    /// `set(name, value)` — sets or replaces it.
    m.function("set") { args in
        guard args.count == 2, case .string(let name) = args[0], case .string(let value) = args[1] else {
            throw Swiftalk.Error.type("Env.set(name, value) takes two Strings")
        }
        guard setenv(name, value, 1) == 0 else {
            throw Swiftalk.Error.type("Env.set(\(name)): \(String(cString: strerror(errno)))")
        }
        return .nil
    }

    /// `unset(name)` — removes it; removing what is not there is fine.
    m.function("unset") { args in
        guard args.count == 1, case .string(let name) = args[0] else {
            throw Swiftalk.Error.type("Env.unset(name) takes one String")
        }
        guard unsetenv(name) == 0 else {
            throw Swiftalk.Error.type("Env.unset(\(name)): \(String(cString: strerror(errno)))")
        }
        return .nil
    }

    /// `all()` — every variable, a `[String: String]`.
    m.function("all") { args in
        guard args.isEmpty else { throw Swiftalk.Error.type("Env.all() takes no arguments") }
        var table: [Swiftalk.Value: Swiftalk.Value] = [:]
        var cursor = environ
        while let entry = cursor.pointee {
            let line = String(cString: entry)
            if let eq = line.firstIndex(of: "=") {
                table[.string(String(line[..<eq]))] = .string(String(line[line.index(after: eq)...]))
            }
            cursor += 1
        }
        return .dictionary(table)
    }

    /// `platform` — a constant export: the OS the interpreter runs on.
    #if os(macOS)
    m.export("platform", .string("darwin"))
    #elseif os(Linux)
    m.export("platform", .string("linux"))
    #else
    m.export("platform", .string("unknown"))
    #endif
    return m
}

/// The entry point the interpreter calls after dlopen: a fresh module,
/// retained for the C boundary — see `Swiftalk.Module`.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
