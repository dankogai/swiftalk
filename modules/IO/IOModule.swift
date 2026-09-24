import Swiftalk

// `IO` — `print` and `debugPrint` (round 189; the core's from round 1 to
// 185, a core-registered module until now). Preimported by the CLI as
// its prelude; `import from "IO"` otherwise. Where the text goes is the
// host's: `Interpreter.output`, stdout by default — `Swiftalk.output`
// reaches it.

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "IO")
    /// `print(x, ...)` — each value's display text, space-separated, a
    /// newline; a String bare, everything else its source form, a type's
    /// own `String` member speaking (round 152).
    m.function("print") { args in
        Swiftalk.output(try args.map(Swiftalk.display).joined(separator: " ") + "\n")
        return .nil
    }
    /// `debugPrint(x, ...)` — `.debugDescription` for everything: quoted
    /// Strings, signed hex numbers — for the programmer's sake (round 37).
    m.function("debugPrint") { args in
        Swiftalk.output(args.map { $0.sourceString(debug: true) }.joined(separator: " ") + "\n")
        return .nil
    }
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
