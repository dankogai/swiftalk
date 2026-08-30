#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Re-entrancy guard for property observers (round 58b): while a
/// property's observer runs, writes to that same property do not
/// re-trigger it — so the canonical `didSet { if .x > 10 { .x = 10 } }`
/// clamp terminates instead of recursing. Keys are per-instance for
/// references (identity exists) and per-type for structs (it doesn't).
/// Thread-local, because each task/coroutine context is its own thread
/// (the baton serializes them, but an observer may suspend).
///
/// Also carries init suppression: observers do not fire while the
/// owning type's init is assigning (Swift's rule).
enum ObserverGuard {
    private final class Box {
        var active: Set<String> = []
    }

    private static let tlsKey: pthread_key_t = {
        var key = pthread_key_t()
        #if canImport(Darwin)
        pthread_key_create(&key) { pointer in
            Unmanaged<AnyObject>.fromOpaque(pointer).release()
        }
        #else
        pthread_key_create(&key) { pointer in
            guard let pointer else { return }
            Unmanaged<AnyObject>.fromOpaque(pointer).release()
        }
        #endif
        return key
    }()

    private static var box: Box {
        if let pointer = pthread_getspecific(tlsKey) {
            return Unmanaged<Box>.fromOpaque(pointer).takeUnretainedValue()
        }
        let fresh = Box()
        pthread_setspecific(tlsKey, Unmanaged.passRetained(fresh).toOpaque())
        return fresh
    }

    /// Claims `key`; false when already active (skip the observers).
    static func enter(_ key: String) -> Bool {
        box.active.insert(key).inserted
    }
    static func leave(_ key: String) {
        box.active.remove(key)
    }

    /// Claims every key at once (init suppression); returns the keys
    /// actually claimed, for the paired `leave(all:)`.
    static func enter(all keys: [String]) -> [String] {
        keys.filter { enter($0) }
    }
    static func leave(all keys: [String]) {
        for key in keys { leave(key) }
    }
}
