#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension Swiftalk {
    /// A spawned concurrent computation (§12, round 53): what
    /// `Task { ... }` / `async { ... }` returns and `await` joins.
    /// Identity equality, like Function and Sequence.
    public final class TaskObject: Hashable {
        enum State {
            case running            // spawn is eager: born running
            case done(Value)
            case failed(Swift.Error)
        }
        let body: FunctionObject
        /// Both guarded by the owning Scheduler's mutex.
        var state: State = .running
        var awaiters: [Scheduler.Context] = []

        init(body: FunctionObject) {
            self.body = body
        }

        public static func == (lhs: TaskObject, rhs: TaskObject) -> Bool {
            lhs === rhs
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}

/// The cooperative scheduler (§12, round 53): swiftalk's `async`/`await`
/// rides the round-52 substrate — every task is a green thread (a real
/// pthread, parked), and a single baton guarantees exactly one context
/// ever executes interpreter code. Execution interleaves only at
/// suspension points (`await`, `sleep`), so programs stay deterministic
/// and the interpreter stays single-threaded in effect.
///
/// Contexts: the `main` context is the top level (round 53 allows
/// top-level `await` — eval drives the loop); every spawned Task adds
/// one. `await`/`sleep`/`Task {}` find the current context through a
/// thread-local, which is what makes swiftalk *colorless*: any function
/// may await, because asynchrony is a property of the running context,
/// not of the function — the same dynamic rule as round 52's `yield`.
final class Scheduler {
    final class Context {
        let task: TaskObject?              // nil for the main (top-level) context
        unowned let scheduler: Scheduler
        init(task: TaskObject?, scheduler: Scheduler) {
            self.task = task
            self.scheduler = scheduler
        }
    }

    /// Thrown into parked task contexts at shutdown so their threads
    /// can unwind and exit; never caught by any evaluator `catch`.
    struct Cancelled: Swift.Error {}

    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private let cond: UnsafeMutablePointer<pthread_cond_t>
    private(set) var main: Context! = nil
    private var running: Context?          // the baton: who may execute interpreter code
    private var ready: [Context] = []      // resumable, FIFO
    private var sleepers: [(deadline: Double, ctx: Context)] = []
    private var cancelled = false

    init() {
        mutex = .allocate(capacity: 1)
        cond = .allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(cond, nil)
        main = Context(task: nil, scheduler: self)
        running = main                     // the top level holds the baton from birth
    }

    deinit {
        // Task threads retain the scheduler until they exit, so by the
        // time deinit runs no thread can still be using these.
        pthread_mutex_destroy(mutex)
        pthread_cond_destroy(cond)
        mutex.deallocate()
        cond.deallocate()
    }

    // MARK: the current context (thread-local)

    fileprivate static let tlsKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    /// The context whose code this thread is running — main during a
    /// top-level eval, the task's own inside a task body, nil inside a
    /// round-52 coroutine body (which is why await errors there).
    static var current: Context? {
        guard let pointer = pthread_getspecific(tlsKey) else { return nil }
        return Unmanaged<Context>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Installs `ctx` as this thread's context; returns what to restore.
    static func activate(_ ctx: Context) -> UnsafeMutableRawPointer? {
        let previous = pthread_getspecific(tlsKey)
        pthread_setspecific(tlsKey, Unmanaged.passUnretained(ctx).toOpaque())
        return previous
    }
    static func restore(_ previous: UnsafeMutableRawPointer?) {
        pthread_setspecific(tlsKey, previous)
    }

    // MARK: suspension points

    /// `Task { body }` — eager, the JS way: the newborn runs at once,
    /// until *it* suspends or completes; the spawner resumes next.
    func spawn(_ body: FunctionObject, from me: Context) throws -> Value {
        let task = TaskObject(body: body)
        let ctx = Context(task: task, scheduler: self)
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        ready.insert(me, at: 0)            // I am first in line behind the newborn
        running = ctx
        if let error = startThread(ctx) {
            ready.removeFirst()
            running = me
            throw error
        }
        try waitUntilRunning(me)
        return .task(task)
    }

    /// `await t` — the fast path returns a settled result; otherwise
    /// park as an awaiter until the task completes (its error rethrows
    /// here, at every await of it).
    func awaitTask(_ task: TaskObject, from me: Context) throws -> Value {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        while true {
            switch task.state {
            case .done(let value):  return value
            case .failed(let error): throw error
            case .running:          break
            }
            task.awaiters.append(me)
            running = nil
            try waitUntilRunning(me)
        }
    }

    /// `sleep(seconds)` — suspend the current context; others run.
    func sleep(seconds: Double, from me: Context) throws {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        sleepers.append((deadline: Scheduler.now() + seconds, ctx: me))
        running = nil
        try waitUntilRunning(me)
    }

    /// Interpreter teardown: wake every parked task into a `Cancelled`
    /// throw so its thread unwinds and exits.
    func shutdown() {
        pthread_mutex_lock(mutex)
        cancelled = true
        pthread_cond_broadcast(cond)
        pthread_mutex_unlock(mutex)
    }

    // MARK: the loop

    /// The scheduling loop, run symmetrically by whichever context is
    /// parked: whoever notices the baton is free seats the next ready
    /// context, handles timers, and detects deadlock. Lock held on
    /// entry, on return, and on throw.
    private func waitUntilRunning(_ me: Context) throws {
        while running !== me {
            if cancelled { throw Cancelled() }
            if running == nil {
                wakeDueSleepers()
                if !ready.isEmpty {
                    let next = ready.removeFirst()
                    running = next
                    if next === me { break }
                    pthread_cond_broadcast(cond)   // it is parked in this same loop
                } else if let deadline = sleepers.map(\.deadline).min() {
                    timedWait(until: deadline)
                } else {
                    // Nothing ready, nothing sleeping, nobody running:
                    // what I wait for can never happen. Claim the baton
                    // and fail — inside a task, this fails the task and
                    // wakes *its* awaiters, so the error propagates.
                    running = me
                    throw SwiftalkError.type(
                        "deadlock: 'await' on a Task that can never complete")
                }
            } else {
                pthread_cond_wait(cond, mutex)
            }
        }
    }

    /// Task-body completion (on the task's own thread): publish the
    /// outcome, ready the awaiters, free the baton, and let whoever is
    /// parked schedule next.
    fileprivate func complete(_ task: TaskObject, _ outcome: TaskObject.State) {
        pthread_mutex_lock(mutex)
        task.state = outcome
        ready.append(contentsOf: task.awaiters)
        task.awaiters = []
        running = nil
        pthread_cond_broadcast(cond)
        pthread_mutex_unlock(mutex)
    }

    private func wakeDueSleepers() {
        let time = Scheduler.now()
        let due = sleepers.filter { $0.deadline <= time }
        guard !due.isEmpty else { return }
        sleepers.removeAll { $0.deadline <= time }
        ready.append(contentsOf: due.map(\.ctx))
    }

    private static func now() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_REALTIME, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }

    private func timedWait(until deadline: Double) {
        let whole = deadline.rounded(.down)
        var ts = timespec(tv_sec: Int(whole),
                          tv_nsec: min(999_999_999, Int((deadline - whole) * 1e9)))
        pthread_cond_timedwait(cond, mutex, &ts)
    }

    // MARK: the task thread

    private func startThread(_ ctx: Context) -> Swift.Error? {
        var attr = pthread_attr_t()
        pthread_attr_init(&attr)
        pthread_attr_setdetachstate(&attr, Int32(PTHREAD_CREATE_DETACHED))
        // Frame size is the recursion budget (round 45) — full stack.
        pthread_attr_setstacksize(&attr, 1 << 23)
        let box = TaskThreadBox(scheduler: self, context: ctx)
        let argument = Unmanaged.passRetained(box).toOpaque()
        #if canImport(Darwin)
        var thread: pthread_t? = nil
        #else
        var thread = pthread_t()
        #endif
        let rc = pthread_create(&thread, &attr, taskThreadMain, argument)
        pthread_attr_destroy(&attr)
        guard rc == 0 else {
            Unmanaged<TaskThreadBox>.fromOpaque(argument).release()
            return SwiftalkError.type("could not start a task thread (errno \(rc))")
        }
        return nil
    }
}

/// Keeps the scheduler (and the context) alive for as long as the task
/// thread lives — mutex and condvar must outlive every parked thread.
private final class TaskThreadBox {
    let scheduler: Scheduler
    let context: Scheduler.Context
    init(scheduler: Scheduler, context: Scheduler.Context) {
        self.scheduler = scheduler
        self.context = context
    }
}

#if canImport(Darwin)
private func taskThreadMain(_ argument: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    taskThreadBody(argument)
    return nil
}
#else
private func taskThreadMain(_ argument: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let argument else { return nil }
    taskThreadBody(argument)
    return nil
}
#endif

private func taskThreadBody(_ argument: UnsafeMutableRawPointer) {
    let box = Unmanaged<TaskThreadBox>.fromOpaque(argument).takeRetainedValue()
    pthread_setspecific(Scheduler.tlsKey,
                        Unmanaged.passUnretained(box.context).toOpaque())
    let task = box.context.task!
    do {
        // `return` from the body is the task's value (run() catches the
        // ReturnSignal); errors settle the task and rethrow at await.
        let result = try run(task.body, ordered: []).result
        box.scheduler.complete(task, .done(result))
    } catch is Scheduler.Cancelled {
        // interpreter teardown: exit without a word
    } catch {
        box.scheduler.complete(task, .failed(error))
    }
}
