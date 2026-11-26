import XCTest
@testable import LinkrunnerKit

final class AwaitTokenTests: XCTestCase {

    func testReturnsNilAfterTimeoutWhenInitializeIsNeverCalled() async {
        let start = Date()
        let token = await LinkrunnerSDK.shared.awaitToken(timeoutMs: 300)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(token)
        XCTAssertGreaterThanOrEqual(elapsed, 0.3)
        XCTAssertLessThan(elapsed, 1.5)
    }

    func testReturnsPromptlyWhenTheCallingTaskIsCancelled() async {
        let start = Date()
        let task = Task { await LinkrunnerSDK.shared.awaitToken(timeoutMs: 5_000) }
        task.cancel()
        let token = await task.value

        XCTAssertNil(token)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
