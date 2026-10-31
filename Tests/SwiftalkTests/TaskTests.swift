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
            let t1 = async { log.append(1); Task.sleep(0.03); log.append(3) }
            let t2 = async { log.append(2); Task.sleep(0.01); log.append(4) }
            Task.sleep(0.05)
            log
            """) == .array([.int(1), .int(2), .int(4), .int(3)]))
        // awaiting does the driving too — no top-level sleep needed
        #expect(try eval("""
            let t1 = async { Task.sleep(0.02); 1 }
            let t2 = async { Task.sleep(0.01); 2 }
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
                var t = async { Task.sleep(0.01); await t }
                await t
                """)
        }
    }

    @Test("after a deadlock error the scheduler carries on: sleep, a fresh task, a REPL-style second eval (round 241)")
    func afterDeadlock() throws {
        // the thrower used to stay in the failed task's awaiters, so the dead
        // task was readied again and the next suspension hung forever
        #expect(try eval("""
            var box = [Task]()
            let d = Task { Task.sleep(0.01); await box[0] }
            box.append(d)
            let first = eval("await d")
            Task.sleep(0.01)
            let second = await Task { Task.sleep(0.01); 1 }
            [first.failure != nil, second == 1, (await Task { 2 }) == 2]
            """) == .array([.bool(true), .bool(true), .bool(true)]))
        // two tasks awaiting each other, then life goes on
        #expect(try eval("""
            var bx = [Task]()
            let p = Task { Task.sleep(0.01); await bx[1] }
            let q = Task { Task.sleep(0.01); await bx[0] }
            bx.append(p)
            bx.append(q)
            let r = eval("await p")
            Task.sleep(0.01)
            r.failure != nil ? await Task { 3 } : 0
            """) == .int(3))
        // across a persistent interpreter's evals, as the REPL does it
        let interp = try interpreter()
        #expect(throws: SwiftalkError.self) {
            try interp.eval("""
                var t = async { Task.sleep(0.01); await t }
                await t
                """)
        }
        #expect(try interp.eval("Task.sleep(0.01)\nawait Task { 5 }") == .int(5))
    }

    @Test("what Task refuses: builtins, parameters, and non-Functions")
    func spawnGuards() throws {
        #expect(throws: SwiftalkError.self) { try eval("Task(print)") }
        #expect(throws: SwiftalkError.self) { try eval("let f = { x in x }\nTask(f)") }
        #expect(throws: SwiftalkError.self) { try eval("Task(42)") }
    }

    @Test("tasks persist across a persistent interpreter's evals (the REPL's world)")
    func replPersistence() throws {
        let interp = try interpreter(relaxed: true)          // the prelude: Task.sleep is the Task module's (round 192)
        _ = try interp.eval("let t = async { Task.sleep(0.01); 42 }")
        #expect(try interp.eval("await t") == .int(42))
    }

    @Test("an abandoned parked task is cancelled at teardown — nothing hangs")
    func teardown() throws {
        // one-shot eval: the task parks in sleep, is never awaited, and
        // must not keep anything alive after the interpreter is gone
        #expect(try eval("let t = async { Task.sleep(60.0); 1 }\n42") == .int(42))
    }
}
