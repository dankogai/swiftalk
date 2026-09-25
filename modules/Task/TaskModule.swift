import Swiftalk

// `Task` — the module that extends the core type `Task` (round 192):
// `Task.sleep(seconds)` (round 53's top-level `sleep`, a core static from
// round 185 until now, as Swift spells it). Suspends only the *current*
// context — parked tasks run meanwhile; at the top level it doubles as
// "run the loop for a while". Exports nothing by name; preimported by
// the CLI, `import from "Task"` otherwise.

func sleep(_ args: [Swiftalk.Value]) throws -> Swiftalk.Value {
    let seconds: Double
    switch (args.count, args.first) {
    case (1, .double(let d)?) where d >= 0: seconds = d
    case (1, .int(let i)?) where i >= 0:    seconds = Double(i)
    default:
        throw Swiftalk.Error.type("Task.sleep(seconds) — a non-negative Int or Double")
    }
    try Swiftalk.sleep(seconds: seconds)
    return .nil
}

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "Task")
    let sleepFunction = Swiftalk.Module(name: "-")
    sleepFunction.function("sleep", sleep)
    m.static("Task", "sleep", sleepFunction.value(named: "sleep")!)
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
