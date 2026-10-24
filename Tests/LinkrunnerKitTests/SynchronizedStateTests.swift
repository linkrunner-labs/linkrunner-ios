import XCTest
@testable import LinkrunnerKit

final class SynchronizedStateTests: XCTestCase {
    // Heap-allocated like a real AdServices token; short strings are stored inline and never crash.
    private func longToken() -> String {
        String(repeating: "A", count: 320) + UUID().uuidString
    }

    func testConcurrentAttributionTokenReadsAndWritesDoNotCrash() async {
        let sdk = LinkrunnerSDK.shared
        let token = longToken()
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<16 {
                group.addTask {
                    for _ in 0..<20_000 {
                        if worker % 2 == 0 {
                            sdk.cachedAttributionToken = token + "\(worker)"
                        } else if let read = sdk.cachedAttributionToken {
                            XCTAssertTrue(read.hasPrefix("AAAA"))
                        }
                    }
                }
            }
        }
        sdk.cachedAttributionToken = nil
    }

    func testSynchronizedKeepsLastWrite() {
        let box = Synchronized(wrappedValue: "first")
        box.wrappedValue = "second"
        XCTAssertEqual(box.wrappedValue, "second")
    }
}
