import XCTest
@testable import LinkrunnerKit

final class QueueStubURLProtocol: URLProtocol {
    struct Sent {
        let path: String
        let body: [String: Any]
        let at: Date
    }
    enum Reply {
        case status(Int, [String: Any])
        case error(URLError.Code)
    }

    private static let lock = NSLock()
    private static var _sent: [Sent] = []
    private static var _handler: (String, [String: Any]) -> Reply = { _, _ in .status(200, ["status": 200]) }

    static var sent: [Sent] { lock.lock(); defer { lock.unlock() }; return _sent }
    static func reset(_ handler: @escaping (String, [String: Any]) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        _sent = []
        _handler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self._sent.append(Sent(path: path, body: body, at: Date()))
        let reply = Self._handler(path, body)
        Self.lock.unlock()

        switch reply {
        case .status(let code, let json):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: json)) ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        case .error(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    private static func bodyData(_ request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class RequestQueueSenderTests: XCTestCase {

    private var dir: URL!
    private var store: EventQueueStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var session: URLSession!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = EventQueueStore(fileURL: dir.appendingPathComponent("q.sqlite"))
        suiteName = "lr-queue-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QueueStubURLProtocol.self]
        session = URLSession(configuration: config)
        QueueStubURLProtocol.reset { _, _ in .status(200, ["status": 200]) }
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeSender(
        token: String? = "tok_123",
        config: RequestQueueSender.Config = .init(minIntervalMs: 0, backoffBaseMs: 20, backoffMaxMs: 200, initWaitMs: 300, gatePollMs: 20),
        responses: ResponseLog? = nil
    ) -> (RequestQueueSender, InitGate) {
        let gate = InitGate(defaults: defaults)
        let session = self.session!
        let transport: RequestQueueSender.Transport = { endpoint, body in
            var request = URLRequest(url: URL(string: "https://api.linkrunner.io" + endpoint)!)
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? SendableDictionary
            return ((response as! HTTPURLResponse).statusCode, json)
        }
        let sender = RequestQueueSender(
            store: store,
            gate: gate,
            transport: transport,
            tokenProvider: { token },
            installIdProvider: { "install_1" },
            onResponse: { kind, _ in responses?.append(kind) },
            config: config
        )
        return (sender, gate)
    }

    private func enqueue(_ kind: QueuedRequestKind, _ body: [String: Any], priority: Int = 1) {
        let payload = LinkrunnerSDK.queuePayload(for: body)!
        store.insert(kind: kind.rawValue, payload: payload, priority: priority, now: Int64(Date().timeIntervalSince1970 * 1000))
    }

    private func markInitSent() {
        InitGate(defaults: defaults).markSent(installId: "install_1")
    }

    func testSendsInFifoOrderWithTokenInjectedButNotStored() async {
        markInitSent()
        enqueue(.event, ["token": "should_not_store", "event_name": "a"])
        enqueue(.signup, ["user_data": ["id": "u1"]], priority: 0)
        enqueue(.event, ["event_name": "b"])
        XCTAssertFalse(store.first()!.payload.contains("should_not_store"))

        let (sender, _) = makeSender()
        await sender.kick()
        await sender.waitUntilIdle()

        let sent = QueueStubURLProtocol.sent
        XCTAssertEqual(sent.map(\.path), ["/api/client/capture-event", "/api/client/trigger", "/api/client/capture-event"])
        XCTAssertEqual(sent.map { $0.body["event_name"] as? String }, ["a", nil, "b"])
        XCTAssertTrue(sent.allSatisfy { $0.body["token"] as? String == "tok_123" })
        XCTAssertEqual(store.count(), 0)
    }

    func testInitIsSentBeforeEarlierRowsOnFreshInstall() async {
        enqueue(.event, ["event_name": "early"])
        enqueue(.initialize, ["install_instance_id": "install_1"], priority: 0)
        enqueue(.event, ["event_name": "late"])

        let (sender, gate) = makeSender()
        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertEqual(QueueStubURLProtocol.sent.map(\.path).first, "/api/client/init")
        XCTAssertEqual(QueueStubURLProtocol.sent.compactMap { $0.body["event_name"] as? String }, ["early", "late"])
        XCTAssertTrue(gate.isSent(installId: "install_1"))
    }

    func testRowsWaitForMissingInitThenReleaseAfterTimeout() async {
        enqueue(.event, ["event_name": "a"])
        let (sender, gate) = makeSender()

        let start = Date()
        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.28)
        XCTAssertEqual(QueueStubURLProtocol.sent.count, 1)
        XCTAssertTrue(gate.isOpen(installId: "install_1"))
        XCTAssertFalse(gate.isSent(installId: "install_1"))
    }

    func testInitRetriesAndHoldsEventsWhileOffline() async {
        var initCalls = 0
        QueueStubURLProtocol.reset { path, _ in
            if path == "/api/client/init" {
                initCalls += 1
                return initCalls < 3 ? .error(.notConnectedToInternet) : .status(200, [:])
            }
            return .status(200, [:])
        }
        enqueue(.initialize, ["install_instance_id": "install_1"], priority: 0)
        enqueue(.event, ["event_name": "a"])

        let (sender, _) = makeSender()
        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertEqual(QueueStubURLProtocol.sent.map(\.path),
                       ["/api/client/init", "/api/client/init", "/api/client/init", "/api/client/capture-event"])
    }

    func testRequestsArePaced() async {
        markInitSent()
        for i in 0..<6 { enqueue(.event, ["event_name": "e\(i)"]) }
        let (sender, _) = makeSender(config: .init(minIntervalMs: 100, backoffBaseMs: 20, backoffMaxMs: 200, initWaitMs: 300, gatePollMs: 20))

        await sender.kick()
        await sender.waitUntilIdle()

        let times = QueueStubURLProtocol.sent.map(\.at)
        XCTAssertEqual(times.count, 6)
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), 0.09)
        }
    }

    func testRetriesServerErrorsRateLimitsAndNetworkErrors() async {
        markInitSent()
        var calls = 0
        QueueStubURLProtocol.reset { _, _ in
            calls += 1
            switch calls {
            case 1: return .status(503, [:])
            case 2: return .status(429, [:])
            case 3: return .error(.timedOut)
            case 4: return .status(408, [:])
            default: return .status(200, [:])
            }
        }
        enqueue(.event, ["event_name": "a"])
        let (sender, _) = makeSender()

        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertEqual(QueueStubURLProtocol.sent.count, 5)
        XCTAssertEqual(store.count(), 0)
    }

    func testBackoffGrowsBetweenAttempts() async {
        markInitSent()
        var calls = 0
        QueueStubURLProtocol.reset { _, _ in
            calls += 1
            return calls < 4 ? .status(500, [:]) : .status(200, [:])
        }
        enqueue(.event, ["event_name": "a"])
        let (sender, _) = makeSender(config: .init(minIntervalMs: 0, backoffBaseMs: 50, backoffMaxMs: 1_000, initWaitMs: 300, gatePollMs: 20))

        await sender.kick()
        await sender.waitUntilIdle()

        let times = QueueStubURLProtocol.sent.map(\.at)
        XCTAssertEqual(times.count, 4)
        let gaps = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }
        XCTAssertGreaterThanOrEqual(gaps[0], 0.045)
        XCTAssertGreaterThanOrEqual(gaps[1], 0.095)
        XCTAssertGreaterThanOrEqual(gaps[2], 0.19)
    }

    func testClientErrorsDropTheRowAndMoveOn() async {
        markInitSent()
        QueueStubURLProtocol.reset { _, body in
            body["event_name"] as? String == "bad" ? .status(400, [:]) : .status(200, [:])
        }
        enqueue(.event, ["event_name": "bad"])
        enqueue(.event, ["event_name": "good"])
        let (sender, _) = makeSender()

        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertEqual(QueueStubURLProtocol.sent.compactMap { $0.body["event_name"] as? String }, ["bad", "good"])
        XCTAssertEqual(store.count(), 0)
    }

    func testRejectedInitReleasesTheGate() async {
        QueueStubURLProtocol.reset { path, _ in path == "/api/client/init" ? .status(401, [:]) : .status(200, [:]) }
        enqueue(.initialize, ["install_instance_id": "install_1"], priority: 0)
        enqueue(.event, ["event_name": "a"])
        let (sender, gate) = makeSender()

        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertEqual(QueueStubURLProtocol.sent.map(\.path), ["/api/client/init", "/api/client/capture-event"])
        XCTAssertFalse(gate.isSent(installId: "install_1"))
        XCTAssertTrue(gate.isOpen(installId: "install_1"))
    }

    func testSuccessfulResponsesReachTheSkanHandler() async {
        markInitSent()
        let log = ResponseLog()
        enqueue(.event, ["event_name": "a"])
        enqueue(.capturePayment, ["payment_id": "p"], priority: 0)
        let (sender, _) = makeSender(responses: log)

        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertEqual(log.kinds, [.event, .capturePayment])
        XCTAssertEqual(QueuedRequestKind.event.skanSource, "event")
        XCTAssertEqual(QueuedRequestKind.capturePayment.skanSource, "payment")
        XCTAssertEqual(QueuedRequestKind.signup.skanSource, "signup")
        XCTAssertNil(QueuedRequestKind.setUserData.skanSource)
    }

    func testNothingIsSentWithoutAToken() async {
        markInitSent()
        enqueue(.event, ["event_name": "a"])
        let (sender, _) = makeSender(token: nil)

        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertTrue(QueueStubURLProtocol.sent.isEmpty)
        XCTAssertEqual(store.count(), 1)
    }

    func testExpiredRowsAreNotSent() async {
        markInitSent()
        let old = Int64(Date().timeIntervalSince1970 * 1000) - EventQueueStore.ttlMs - 1_000
        store.insert(kind: "event", payload: "{\"event_name\":\"old\"}", priority: 1, now: old)
        enqueue(.event, ["event_name": "fresh"])
        let (sender, _) = makeSender()

        await sender.kick()
        await sender.waitUntilIdle()

        XCTAssertEqual(QueueStubURLProtocol.sent.compactMap { $0.body["event_name"] as? String }, ["fresh"])
    }

    func testKickWithResetWakesALongBackoff() async {
        markInitSent()
        var calls = 0
        QueueStubURLProtocol.reset { _, _ in
            calls += 1
            return calls == 1 ? .error(.notConnectedToInternet) : .status(200, [:])
        }
        enqueue(.event, ["event_name": "a"])
        let (sender, _) = makeSender(config: .init(minIntervalMs: 0, backoffBaseMs: 60_000, backoffMaxMs: 60_000, initWaitMs: 300, gatePollMs: 20))

        let start = Date()
        await sender.kick()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await sender.kick(resetBackoff: true)
        await sender.waitUntilIdle()

        XCTAssertEqual(QueueStubURLProtocol.sent.count, 2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testRetryClassification() {
        XCTAssertEqual(RequestQueueSender.classify(status: 200), .sent)
        XCTAssertEqual(RequestQueueSender.classify(status: 201), .sent)
        XCTAssertEqual(RequestQueueSender.classify(status: 408), .retry)
        XCTAssertEqual(RequestQueueSender.classify(status: 429), .retry)
        XCTAssertEqual(RequestQueueSender.classify(status: 502), .retry)
        XCTAssertEqual(RequestQueueSender.classify(status: 400), .drop)
        XCTAssertEqual(RequestQueueSender.classify(status: 403), .drop)
        XCTAssertEqual(RequestQueueSender.classify(error: URLError(.notConnectedToInternet)), .retry)
        XCTAssertEqual(RequestQueueSender.classify(error: URLError(.secureConnectionFailed)), .retry)
        XCTAssertEqual(RequestQueueSender.classify(error: URLError(.badURL)), .drop)
        XCTAssertEqual(RequestQueueSender.classify(error: NSError(domain: "x", code: 1)), .drop)
    }
}

final class ResponseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _kinds: [QueuedRequestKind] = []
    var kinds: [QueuedRequestKind] { lock.lock(); defer { lock.unlock() }; return _kinds }
    func append(_ kind: QueuedRequestKind) { lock.lock(); _kinds.append(kind); lock.unlock() }
}
