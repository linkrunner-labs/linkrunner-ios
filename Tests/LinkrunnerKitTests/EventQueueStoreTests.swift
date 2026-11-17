import XCTest
@testable import LinkrunnerKit

final class EventQueueStoreTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(maxRows: Int = EventQueueStore.maxRows,
                           maxBytes: Int = EventQueueStore.maxBytes,
                           maxMemoryRows: Int = EventQueueStore.maxMemoryRows) -> EventQueueStore {
        EventQueueStore(fileURL: dir.appendingPathComponent("q.sqlite"),
                        maxRows: maxRows, maxBytes: maxBytes, maxMemoryRows: maxMemoryRows)
    }

    func testInsertReadDeleteIsFifo() {
        let store = makeStore()
        store.insert(kind: "event", payload: "{\"n\":1}", priority: 1, now: 10)
        store.insert(kind: "init", payload: "{\"n\":2}", priority: 0, now: 20)
        XCTAssertTrue(store.isPersistent)
        XCTAssertEqual(store.count(), 2)

        let first = store.first()
        XCTAssertEqual(first?.payload, "{\"n\":1}")
        XCTAssertEqual(store.first(kind: "init")?.payload, "{\"n\":2}")

        store.delete(id: first!.id)
        XCTAssertEqual(store.first()?.payload, "{\"n\":2}")
        XCTAssertEqual(store.count(), 1)
    }

    func testRowsSurviveReopen() {
        makeStore().insert(kind: "event", payload: "{}", priority: 1, now: 1)
        let reopened = makeStore()
        XCTAssertEqual(reopened.count(), 1)
        XCTAssertEqual(reopened.first()?.kind, "event")
    }

    func testRowCapDropsOldestLowPriorityFirst() {
        let store = makeStore(maxRows: 3)
        store.insert(kind: "init", payload: "{\"h\":1}", priority: 0, now: 1)
        store.insert(kind: "event", payload: "{\"l\":1}", priority: 1, now: 2)
        store.insert(kind: "event", payload: "{\"l\":2}", priority: 1, now: 3)
        store.insert(kind: "event", payload: "{\"l\":3}", priority: 1, now: 4)

        XCTAssertEqual(store.count(), 3)
        var payloads: [String] = []
        while let row = store.first() { payloads.append(row.payload); store.delete(id: row.id) }
        XCTAssertEqual(payloads, ["{\"h\":1}", "{\"l\":2}", "{\"l\":3}"])
    }

    func testRowCapDropsOldestWhenOnlyHighPriorityRemains() {
        let store = makeStore(maxRows: 2)
        store.insert(kind: "signup", payload: "{\"h\":1}", priority: 0, now: 1)
        store.insert(kind: "signup", payload: "{\"h\":2}", priority: 0, now: 2)
        store.insert(kind: "signup", payload: "{\"h\":3}", priority: 0, now: 3)

        XCTAssertEqual(store.count(), 2)
        XCTAssertEqual(store.first()?.payload, "{\"h\":2}")
    }

    func testByteCapIsEnforced() {
        let store = makeStore(maxBytes: 25)
        store.insert(kind: "event", payload: String(repeating: "a", count: 10), priority: 1, now: 1)
        store.insert(kind: "event", payload: String(repeating: "b", count: 10), priority: 1, now: 2)
        store.insert(kind: "event", payload: String(repeating: "c", count: 10), priority: 1, now: 3)

        XCTAssertEqual(store.count(), 2)
        XCTAssertEqual(store.first()?.payload, String(repeating: "b", count: 10))
    }

    func testPurgeRemovesRowsOlderThanSevenDays() {
        let store = makeStore()
        let now: Int64 = 10 * 24 * 60 * 60 * 1000
        store.insert(kind: "event", payload: "{\"old\":1}", priority: 1, now: now - EventQueueStore.ttlMs - 1)
        store.insert(kind: "event", payload: "{\"new\":1}", priority: 1, now: now - 1000)

        XCTAssertEqual(store.purgeExpired(now: now), 1)
        XCTAssertEqual(store.count(), 1)
        XCTAssertEqual(store.first()?.payload, "{\"new\":1}")
    }

    func testRetryAndResetBackoff() {
        let store = makeStore()
        store.insert(kind: "event", payload: "{}", priority: 1, now: 100)
        let row = store.first()!
        store.scheduleRetry(id: row.id, attempts: 3, nextAttemptAt: 9_999)
        XCTAssertEqual(store.first()?.attempts, 3)
        XCTAssertEqual(store.first()?.nextAttemptAt, 9_999)

        store.resetBackoff(now: 500)
        XCTAssertEqual(store.first()?.nextAttemptAt, 500)
        XCTAssertEqual(store.first()?.attempts, 3)
    }

    func testCorruptFileIsRecreated() throws {
        let url = dir.appendingPathComponent("q.sqlite")
        try Data("not a database at all, just bytes".utf8).write(to: url)

        let store = makeStore()
        store.insert(kind: "event", payload: "{}", priority: 1, now: 1)
        XCTAssertTrue(store.isPersistent)
        XCTAssertEqual(store.count(), 1)
    }

    func testUnopenablePathFallsBackToBoundedMemory() throws {
        let blocker = dir.appendingPathComponent("file")
        try Data().write(to: blocker)
        let store = EventQueueStore(fileURL: blocker.appendingPathComponent("q.sqlite"), maxMemoryRows: 3)

        store.insert(kind: "init", payload: "{\"h\":1}", priority: 0, now: 1)
        for i in 0..<5 {
            store.insert(kind: "event", payload: "{\"l\":\(i)}", priority: 1, now: Int64(2 + i))
        }
        XCTAssertFalse(store.isPersistent)
        XCTAssertEqual(store.count(), 3)
        XCTAssertEqual(store.first()?.payload, "{\"h\":1}")

        let first = store.first()!
        store.delete(id: first.id)
        XCTAssertEqual(store.first()?.payload, "{\"l\":3}")
    }

    func testMemoryFallbackIsBoundedByBytes() {
        let store = EventQueueStore(fileURL: nil)
        let big = String(repeating: "x", count: 200 * 1024)
        for i in 0..<10 {
            store.insert(kind: "event", payload: big, priority: 1, now: Int64(i))
        }
        XCTAssertEqual(store.count(), 5)
    }

    func testNilPathKeepsRowsInMemory() {
        let store = EventQueueStore(fileURL: nil)
        store.insert(kind: "event", payload: "{}", priority: 1, now: 1)
        XCTAssertFalse(store.isPersistent)
        XCTAssertEqual(store.count(), 1)
    }

    func testQueuePayloadDropsTokenAndKeepsNulls() throws {
        let missing: SendableDictionary? = nil
        let body: SendableDictionary = ["token": "secret-token", "event_name": "x", "event_data": missing as Any]
        let payload = try XCTUnwrap(LinkrunnerSDK.queuePayload(for: body))

        XCTAssertFalse(payload.contains("secret-token"))
        let decoded = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        XCTAssertNil(decoded?["token"])
        XCTAssertEqual(decoded?["event_name"] as? String, "x")
        XCTAssertTrue(decoded?["event_data"] is NSNull)
    }

    func testQueuePayloadRejectsInvalidJson() {
        XCTAssertNil(LinkrunnerSDK.queuePayload(for: ["bad": Date()]))
    }
}
