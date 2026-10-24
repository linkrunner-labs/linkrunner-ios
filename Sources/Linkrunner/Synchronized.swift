import Foundation

/// Serializes every read and write of a value that concurrent SDK calls share.
///
/// `LinkrunnerSDK` is `@unchecked Sendable`, and `initialize`, `setUserData` and
/// `trackEvent` can run at the same time on different threads. An unguarded `String`
/// property can then be released by a writer while a reader is still copying it,
/// which crashes with `EXC_BAD_ACCESS`.
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
}
