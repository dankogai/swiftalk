/// Actors (§12, round 54): serialized mutable state — and swiftalk's
/// FIRST reference type, arriving ahead of `class`. State that is
/// shared must be an actor; state that isn't stays a COW value (§4).
///
/// In round 53's cooperative world there are no data *races*, but
/// there are interleaving hazards: a task that reads-modifies-writes
/// shared state across a suspension point can interleave with another
/// task. An actor serializes that: one caller inside at a time, each
/// call held to the end (round 54's anti-reentrancy divergence from
/// Swift), calls colorless like everything else.
extension Swiftalk {
    /// The declared type: `actor Name { ... }` — properties, methods,
    /// and multi-dispatch inits, exactly a struct's shape (round 46/48
    /// machinery reused); the difference is what instances ARE.
    public final class ActorType: Hashable {
        let name: String
        let propertyOrder: [String]
        let properties: [String: StructType.Property]
        let declEnv: Environment
        var constructor: FunctionObject? = nil
        var methods: [String: FunctionObject] = [:]
        var inits: [FunctionObject] = []

        init(name: String, propertyOrder: [String],
             properties: [String: StructType.Property], declEnv: Environment) {
            self.name = name
            self.propertyOrder = propertyOrder
            self.properties = properties
            self.declEnv = declEnv
        }

        public static func == (lhs: ActorType, rhs: ActorType) -> Bool {
            lhs === rhs
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }

    /// An instance: a reference — `let b = a` aliases, equality is
    /// identity, and mutation through one name is visible through all.
    public final class ActorObject: Hashable {
        let type: ActorType
        /// The isolated state. Reads are open (atomic under the baton);
        /// writes happen only inside the actor's own methods (round 54).
        var storage: [String: Value]

        /// Serialization state — guarded by the scheduler's mutex.
        /// `owner` is the context currently inside a method (`depth`
        /// counts self-reentrant calls); `waiters` queue for entry.
        var owner: Scheduler.Context? = nil
        var depth = 0
        var waiters: [Scheduler.Context] = []

        init(type: ActorType, storage: [String: Value]) {
            self.type = type
            self.storage = storage
        }

        public static func == (lhs: ActorObject, rhs: ActorObject) -> Bool {
            lhs === rhs
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}
