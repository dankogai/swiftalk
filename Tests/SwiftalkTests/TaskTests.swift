import Testing
@testable import Swiftalk

@Suite("async/await: colorless Tasks on the coroutine substrate (§12, round 53)")
struct TaskTests {
    @Test("Task { } / async { } spawn; await joins; async is sugar for Task")
    func basics() throws {
        #expect(try eval("await Task { 42 }") == .int(42))
        #expect(try eval("await async { 42 }") == .int(42))
        #expect(try eval("let f = { 7 }\nawait Task(f)") == .int(7))
        // await binds at unary level, the JS way
        #expect(try eval("await async { 40 } + await async { 2 }") == .int(42))
        // a settled task awaits again — memoized, not re-run
        #expect(try eval("""
            var n = 0
            let t = async { n = n + 1; n }
            [await t, await t, n]
            """) == .array([.int(1), .int(1), .int(1)]))
    }

    @Test("colorless: any function may await — no async marking anywhere")
    func colorless() throws {
        #expect(try eval("let f = { t in await t + 1 }\nf(async { 41 })") == .int(42))
        // ...even a function written before tasks were in sight
        #expect(try eval("[async { 1 }, async { 2 }].map { await $0 * 10 }")
            == .array([.int(10), .int(20)]))
    }

    @Test("spawn is eager, the JS way: the body runs to its first suspension")
    func eagerSpawn() throws {
        #expect(try eval("""
            var log = []
            let t = async { log.append("body") }
            log.append("after")
            log
            """) == .array([.string("body"), .string("after")]))
    }

    @Test("sleep suspends only the current context: tasks interleave")
    func interleaving() throws {
        #expect(try eval("""
            var log = []
            let t1 = async { log.append(1); sleep(0.03); log.append(3) }
            let t2 = async { log.append(2); sleep(0.01); log.append(4) }
            sleep(0.05)
            log
            """) == .array([.int(1), .int(2), .int(4), .int(3)]))
        // awaiting does the driving too — no top-level sleep needed
        #expect(try eval("""
            let t1 = async { sleep(0.02); 1 }
            let t2 = async { sleep(0.01); 2 }
            [await t1, await t2]
            """) == .array([.int(1), .int(2)]))
    }

    @Test("a Task is a value: .Type, identity equality, type lock")
    func taskValues() throws {
        #expect(try eval("async { 1 }.Type == Task") == .bool(true))
        #expect(try eval("async { 1 }.Type.name") == .string("Task"))
        #expect(try eval("let t = async { 1 }\nt == t") == .bool(true))
        #expect(try eval("async { 1 } == async { 1 }") == .bool(false))
        #expect(try eval("let t: Task = async { 1 }\nawait t") == .int(1))
    }

    @Test("a task error settles the task and rethrows at every await")
    func errorPropagation() throws {
        #expect(throws: SwiftalkError.self) { try eval("await async { nil! }") }
        // errors cross task boundaries await by await
        #expect(throws: SwiftalkError.self) {
            try eval("let t = async { nil! }\nawait async { await t }")
        }
        // an error in one task does not poison another
        #expect(try eval("""
            let bad = async { nil! }
            let good = async { 42 }
            await good
            """) == .int(42))
    }

    @Test("await on a non-Task is a type error; await needs a context")
    func awaitGuards() throws {
        #expect(throws: SwiftalkError.self) { try eval("await 42") }
        #expect(throws: SwiftalkError.self) { try eval("await nil") }
        // inside a round-52 coroutine body there is no task context (OPEN)
        #expect(throws: SwiftalkError.self) {
            try eval("let t = async { 1 }\nSequence({ yield await t }).Array()")
        }
    }

    @Test("deadlock is detected, not hung: an await that can never complete")
    func deadlock() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("""
                var t = async { sleep(0.01); await t }
                await t
                """)
        }
    }

    @Test("what Task refuses: builtins, parameters, and non-Functions")
    func spawnGuards() throws {
        #expect(throws: SwiftalkError.self) { try eval("Task(print)") }
        #expect(throws: SwiftalkError.self) { try eval("let f = { x in x }\nTask(f)") }
        #expect(throws: SwiftalkError.self) { try eval("Task(42)") }
    }

    @Test("tasks persist across a persistent interpreter's evals (the REPL's world)")
    func replPersistence() throws {
        let interp = Swiftalk.Interpreter(relaxed: true)
        _ = try interp.eval("let t = async { sleep(0.01); 42 }")
        #expect(try interp.eval("await t") == .int(42))
    }

    @Test("an abandoned parked task is cancelled at teardown — nothing hangs")
    func teardown() throws {
        // one-shot eval: the task parks in sleep, is never awaited, and
        // must not keep anything alive after the interpreter is gone
        #expect(try eval("let t = async { sleep(60.0); 1 }\n42") == .int(42))
    }
}
