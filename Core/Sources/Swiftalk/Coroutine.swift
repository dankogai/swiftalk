#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The coroutine engine (§2.4, round 52): `Sequence(f)` wraps a
/// yielding Function, and each iteration runs the body on a dedicated
/// thread. A tree-walking evaluator cannot suspend its own Swift
/// stack, so suspension is a baton-pass between two real stacks —
/// `yield` parks the body thread and wakes the pulling thread, `next`
/// does the reverse. Exactly one of the two ever runs interpreter
/// code, so the interpreter itself stays single-threaded in effect.
///
/// `yield` is *dynamic*, the Lua way: it suspends the innermost
/// *running* coroutine, found through a thread-local — so a helper
/// function called from the body can yield on its behalf.
final class CoroutineRunner {
    private enum State {
        case idle           // body not running: unstarted, or parked in yield
        case running        // body executing, puller waiting
        case yielded(Value)
        case finished
        case failed(Swift.Error)
    }

    /// Thrown into a parked body when the puller walks away (e.g.
    /// `.prefix` of an infinite sequence): unwinds the interpreter
    /// frames on the body thread so it can exit. Never caught by any
    /// evaluator `catch` — they are all typed.
    struct Cancelled: Swift.Error {}

    private let body: FunctionObject
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private let cond: UnsafeMutablePointer<pthread_cond_t>
    private var state: State = .idle
    private var started = false
    private var cancelled = false

    init(body: FunctionObject) {
        self.body = body
        mutex = .allocate(capacity: 1)
        cond = .allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(cond, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        pthread_cond_destroy(cond)
        mutex.deallocate()
        cond.deallocate()
    }

    /// The innermost running coroutine on *this* thread — what a
    /// `yield` statement suspends. Each body thread registers its own
    /// runner, so nested coroutines resolve naturally.
    fileprivate static let tlsKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()
    static var current: CoroutineRunner? {
        guard let pointer = pthread_getspecific(tlsKey) else { return nil }
        return Unmanaged<CoroutineRunner>.fromOpaque(pointer).takeUnretainedValue()
    }

    // MARK: the pulling side

    /// Resumes the body until its next yield; nil when it returned.
    /// A body error surfaces here, once — later pulls return nil.
    func next() throws -> Value? {
        pthread_mutex_lock(mutex)
        switch state {
        case .finished, .failed:
            pthread_mutex_unlock(mutex)
            return nil
        case .idle:
            break
        case .running, .yielded:
            pthread_mutex_unlock(mutex)
            throw SwiftalkError.type("a coroutine cannot pull from itself")
        }
        state = .running
        if started {
            pthread_cond_broadcast(cond)
        } else {
            started = true
            if let error = spawn() {
                state = .finished
                pthread_mutex_unlock(mutex)
                throw error
            }
        }
        while case .running = state {
            pthread_cond_wait(cond, mutex)
        }
        defer { pthread_mutex_unlock(mutex) }
        switch state {
        case .yielded(let value):
            state = .idle
            return value
        case .finished:
            return nil
        case .failed(let error):
            state = .finished
            throw error
        case .idle, .running:
            fatalError("unreachable coroutine state")
        }
    }

    /// Wakes a parked body into a `Cancelled` throw so its thread can
    /// unwind and exit. Called when the pull side drops the iterator.
    func cancel() {
        pthread_mutex_lock(mutex)
        cancelled = true
        pthread_cond_broadcast(cond)
        pthread_mutex_unlock(mutex)
    }

    // MARK: the body side

    /// What a `yield` statement does: hand the value to the puller and
    /// park until resumed.
    func yieldValue(_ value: Value) throws {
        pthread_mutex_lock(mutex)
        if cancelled {
            pthread_mutex_unlock(mutex)
            throw Cancelled()
        }
        state = .yielded(value)
        pthread_cond_broadcast(cond)
        while !cancelled, !isRunning {
            pthread_cond_wait(cond, mutex)
        }
        let dead = cancelled
        pthread_mutex_unlock(mutex)
        if dead { throw Cancelled() }
    }

    private var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    fileprivate func bodyMain() {
        do {
            // The return value is discarded: `return` *terminates* a
            // coroutine, it does not emit (round 52).
            _ = try run(body, ordered: [])
            finish(.finished)
        } catch is Cancelled {
            // the puller walked away; exit without a word
        } catch {
            finish(.failed(error))
        }
    }

    private func finish(_ terminal: State) {
        pthread_mutex_lock(mutex)
        state = terminal
        pthread_cond_broadcast(cond)
        pthread_mutex_unlock(mutex)
    }

    private func spawn() -> Swift.Error? {
        var attr = pthread_attr_t()
        pthread_attr_init(&attr)
        pthread_attr_setdetachstate(&attr, Int32(PTHREAD_CREATE_DETACHED))
        // Frame size is the recursion budget (round 45's war story) —
        // give the body a full-sized stack, not a thread-pool sliver.
        pthread_attr_setstacksize(&attr, 1 << 23)
        let argument = Unmanaged.passRetained(self).toOpaque()
        #if canImport(Darwin)
        var thread: pthread_t? = nil
        #else
        var thread = pthread_t()
        #endif
        let rc = pthread_create(&thread, &attr, coroutineThreadMain, argument)
        pthread_attr_destroy(&attr)
        guard rc == 0 else {
            Unmanaged<CoroutineRunner>.fromOpaque(argument).release()
            return SwiftalkError.type("could not start a coroutine thread (errno \(rc))")
        }
        return nil
    }
}

#if canImport(Darwin)
private func coroutineThreadMain(_ argument: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    pthread_setspecific(CoroutineRunner.tlsKey, argument)
    let runner = Unmanaged<CoroutineRunner>.fromOpaque(argument).takeRetainedValue()
    runner.bodyMain()
    return nil
}
#else
private func coroutineThreadMain(_ argument: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let argument else { return nil }
    pthread_setspecific(CoroutineRunner.tlsKey, argument)
    let runner = Unmanaged<CoroutineRunner>.fromOpaque(argument).takeRetainedValue()
    runner.bodyMain()
    return nil
}
#endif

/// The pull side's grip on a runner: dropping the iterator (its
/// closure captures this) cancels the parked body thread, so
/// `.prefix(8)` of an infinite coroutine leaks nothing.
final class CoroutineHandle {
    private let runner: CoroutineRunner
    init(_ runner: CoroutineRunner) { self.runner = runner }
    func next() throws -> Value? { try runner.next() }
    deinit { runner.cancel() }
}
