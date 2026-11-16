import XCTest
@testable import LinkrunnerKit

/// Two-phase run against a local mock: queue a burst and kill the process, then relaunch and drain.
/// Skipped unless LR_E2E_PHASE and LINKRUNNER_DEBUG_BASE_URL are set.
final class QueueEndToEndTests: XCTestCase {

    private var phase: String? { ProcessInfo.processInfo.environment["LR_E2E_PHASE"] }
    private let burst = 446

    func testBurstThenKill() async throws {
        try XCTSkipUnless(phase == "burst")
        if let url = EventQueueStore.defaultFileURL() {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        UserDefaults.standard.removeObject(forKey: InitGate.storageKey)

        await LinkrunnerSDK.shared.initialize(token: "e2e_token", disableIdfa: true)

        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<burst {
                group.addTask { await LinkrunnerSDK.shared.trackEvent(eventName: "e2e", eventData: ["i": i]) }
            }
        }
        print("LR_E2E burst_returned_ms=\(Int(Date().timeIntervalSince(start) * 1000))")
        kill(getpid(), SIGKILL)
    }

    func testRelaunchDrains() async throws {
        try XCTSkipUnless(phase == "drain")
        await LinkrunnerSDK.shared.initialize(token: "e2e_token", disableIdfa: true)
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if ProcessInfo.processInfo.environment["LR_E2E_DONE_FILE"].map({ FileManager.default.fileExists(atPath: $0) }) == true {
                return
            }
        }
        XCTFail("mock did not report all events within 120s")
    }
}
