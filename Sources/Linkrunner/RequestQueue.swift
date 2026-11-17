import Foundation

/// What the queue sends. The raw value is stored with each row.
enum QueuedRequestKind: String, CaseIterable, Sendable {
    case initialize = "init"
    case signup = "signup"
    case setUserData = "set_user_data"
    case setCustomerUserId = "set_customer_user_id"
    case integrations = "integrations"
    case event = "event"
    case capturePayment = "capture_payment"
    case removePayment = "remove_payment"
    case pushToken = "push_token"

    var endpoint: String {
        switch self {
        case .initialize: return "/api/client/init"
        case .signup: return "/api/client/trigger"
        case .setUserData: return "/api/client/set-user-data"
        case .setCustomerUserId: return "/api/client/customer-user-id"
        case .integrations: return "/api/client/integrations"
        case .event: return "/api/client/capture-event"
        case .capturePayment: return "/api/client/capture-payment"
        case .removePayment: return "/api/client/remove-captured-payment"
        case .pushToken: return "/api/client/update-push-token"
        }
    }

    /// Source label for SKAN updates read from this request's response.
    var skanSource: String? {
        switch self {
        case .signup: return "signup"
        case .event: return "event"
        case .capturePayment: return "payment"
        default: return nil
        }
    }
}

/// Holds non-init requests until the backend has answered init for this install.
final class InitGate: @unchecked Sendable {
    static let storageKey = "linkrunner_init_sent_install_id"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var sentInstallId: String?
    private var releasedForProcess = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sentInstallId = defaults.string(forKey: Self.storageKey)
    }

    func isSent(installId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sentInstallId == installId
    }

    /// Sent, rejected, or given up on for this process.
    func isOpen(installId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sentInstallId == installId || releasedForProcess
    }

    func markSent(installId: String) {
        lock.lock()
        sentInstallId = installId
        lock.unlock()
        defaults.set(installId, forKey: Self.storageKey)
    }

    /// A rejected or long-missing init must not hold other requests forever.
    func release() {
        lock.lock(); defer { lock.unlock() }
        releasedForProcess = true
    }

    func waitUntilOpen(installId: String, timeoutMs: Int) async {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while !isOpen(installId: installId) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

enum QueueSendOutcome: Equatable {
    case sent
    case retry
    case drop
}

/// The single sender that drains `EventQueueStore` while the process is alive.
actor RequestQueueSender {
    typealias Transport = @Sendable (_ endpoint: String, _ body: SendableDictionary) async throws -> (Int, SendableDictionary?)

    struct Config: Sendable {
        var minIntervalMs: Int64 = 100
        var backoffBaseMs: Int64 = 1_000
        var backoffMaxMs: Int64 = 300_000
        var initWaitMs: Int64 = 30_000
        var gatePollMs: Int64 = 200
    }

    private let store: EventQueueStore
    private let gate: InitGate
    private let transport: Transport
    private let tokenProvider: @Sendable () -> String?
    private let installIdProvider: @Sendable () async -> String
    private let enrich: @Sendable (_ body: SendableDictionary, _ endpoint: String) -> SendableDictionary
    private let onResponse: @Sendable (_ kind: QueuedRequestKind, _ response: SendableDictionary) async -> Void
    private let clock: @Sendable () -> Int64
    private let config: Config

    private var loopTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var wakePending = false
    private var resetPending = false
    private var lastSendAt: Int64 = 0
    private var gateWaitStartedAt: Int64?
    private var idleHandler: (@Sendable () -> Void)?

    init(
        store: EventQueueStore,
        gate: InitGate,
        transport: @escaping Transport,
        tokenProvider: @escaping @Sendable () -> String?,
        installIdProvider: @escaping @Sendable () async -> String,
        enrich: @escaping @Sendable (SendableDictionary, String) -> SendableDictionary = { body, _ in body },
        onResponse: @escaping @Sendable (QueuedRequestKind, SendableDictionary) async -> Void = { _, _ in },
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        config: Config = Config()
    ) {
        self.store = store
        self.gate = gate
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.installIdProvider = installIdProvider
        self.enrich = enrich
        self.onResponse = onResponse
        self.clock = clock
        self.config = config
    }

    var isRunning: Bool { loopTask != nil }

    /// Called whenever the loop stops or waits a long time, so a background task can end.
    func setIdleHandler(_ handler: (@Sendable () -> Void)?) {
        idleHandler = handler
    }

    /// Starts the loop, or wakes it from a wait. `resetBackoff` makes every row due now.
    func kick(resetBackoff: Bool = false) {
        if resetBackoff {
            store.resetBackoff(now: clock())
            resetPending = true
        }
        if loopTask == nil {
            loopTask = Task { await self.run() }
        } else {
            // A kick during a send must still apply after that send schedules its retry.
            wakePending = true
            sleepTask?.cancel()
        }
    }

    /// Resolves when the loop has stopped.
    func waitUntilIdle() async {
        while let task = loopTask { await task.value }
    }

    private func run() async {
        store.purgeExpired(now: clock())
        while !Task.isCancelled {
            if resetPending {
                resetPending = false
                store.resetBackoff(now: clock())
            }
            guard tokenProvider() != nil else { break }
            let installId = await installIdProvider()
            guard let row = nextRow(installId: installId) else {
                if store.count() == 0 { break }
                await sleep(ms: config.gatePollMs)
                continue
            }
            let now = clock()
            if row.nextAttemptAt > now {
                let wait = row.nextAttemptAt - now
                if wait > 5_000 { idleHandler?() }
                await sleep(ms: wait)
                continue
            }
            let sinceLast = now - lastSendAt
            if sinceLast < config.minIntervalMs {
                // Pacing is short and ignores kicks, so a burst of calls cannot skip it.
                try? await Task.sleep(nanoseconds: UInt64(config.minIntervalMs - sinceLast) * 1_000_000)
                continue
            }
            await send(row, installId: installId)
        }
        loopTask = nil
        idleHandler?()
    }

    /// Init goes first until the backend has answered it; strict FIFO after that.
    private func nextRow(installId: String) -> QueuedRequest? {
        if gate.isSent(installId: installId) {
            gateWaitStartedAt = nil
            return store.first()
        }
        if let initRow = store.first(kind: QueuedRequestKind.initialize.rawValue) {
            return initRow
        }
        if gate.isOpen(installId: installId) {
            return store.first()
        }
        let now = clock()
        let started = gateWaitStartedAt ?? now
        gateWaitStartedAt = started
        if now - started >= config.initWaitMs {
            gate.release()
            return store.first()
        }
        return nil
    }

    private func send(_ row: QueuedRequest, installId: String) async {
        lastSendAt = clock()
        guard let kind = QueuedRequestKind(rawValue: row.kind),
              let data = row.payload.data(using: .utf8),
              var body = (try? JSONSerialization.jsonObject(with: data)) as? SendableDictionary,
              let token = tokenProvider() else {
            store.delete(id: row.id)
            return
        }
        body["token"] = token
        body = enrich(body, kind.endpoint)

        let outcome: QueueSendOutcome
        var response: SendableDictionary?
        var status = 0
        do {
            let result = try await transport(kind.endpoint, body)
            status = result.0
            response = result.1
            outcome = Self.classify(status: status)
        } catch {
            outcome = Self.classify(error: error)
        }

        switch outcome {
        case .sent:
            store.delete(id: row.id)
            if kind == .initialize {
                gate.markSent(installId: (body["install_instance_id"] as? String) ?? installId)
            }
            if let response = response { await onResponse(kind, response) }
        case .drop:
            store.delete(id: row.id)
            if kind == .initialize { gate.release() }
        case .retry:
            let attempts = row.attempts + 1
            store.scheduleRetry(id: row.id, attempts: attempts, nextAttemptAt: clock() + backoffMs(attempts: attempts))
        }

        #if DEBUG
        print("Linkrunner: queue \(kind.rawValue) status=\(status) outcome=\(outcome)")
        #endif
    }

    static func classify(status: Int) -> QueueSendOutcome {
        switch status {
        case 200..<300: return .sent
        case 408, 429, 500..<600: return .retry
        default: return .drop
        }
    }

    static func classify(error: Error) -> QueueSendOutcome {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .badURL, .unsupportedURL: return .drop
            default: return .retry
            }
        }
        return .drop
    }

    private func backoffMs(attempts: Int) -> Int64 {
        let exponent = min(max(attempts - 1, 0), 20)
        let base = min(config.backoffBaseMs << Int64(exponent), config.backoffMaxMs)
        let jitter = Int64.random(in: 0...max(base / 5, 1))
        return min(base + jitter, config.backoffMaxMs)
    }

    private func sleep(ms: Int64) async {
        guard ms > 0 else { return }
        if wakePending {
            wakePending = false
            return
        }
        let task = Task<Void, Never> { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
        sleepTask = task
        await task.value
        sleepTask = nil
        wakePending = false
    }
}
