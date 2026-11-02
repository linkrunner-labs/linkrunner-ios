import Foundation

/// Serializes every read and write of a value that concurrent SDK calls share.
///
/// `LinkrunnerSDK` is `@unchecked Sendable`, and `initialize`, `setUserData` and
/// `trackEvent` can run at the same time on different threads. An unguarded `String`
/// property can then be released by a writer while a reader is still copying it,
/// which crashes with `EXC_BAD_ACCESS`.
///
/// A plain get or set is atomic. A check-then-set must go through `$property.withLock`,
/// since a separate get and set can interleave with another writer.
@propertyWrapper
final class Synchronized<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    var projectedValue: Synchronized<Value> { self }

    /// Runs `body` with exclusive access to the value. Must not await or call back into
    /// the same property, since `NSLock` is not reentrant.
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
