import XCTest
@testable import LinkrunnerKit

final class SynchronizedStateTests: XCTestCase {
    // Heap-allocated like a real AdServices token; short strings are stored inline and never crash.
    private func longToken() -> String {
        String(repeating: "A", count: 320) + UUID().uuidString
    }

    override func tearDown() {
        let sdk = LinkrunnerSDK.shared
        sdk.cachedAttributionToken = nil
        sdk.setConsent(LinkrunnerConsent())
        sdk.enablePIIHashing(false)
        sdk.enableTCFConsentCollection(false)
        super.tearDown()
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
                        } else if let read = await sdk.getAttributionToken() {
                            XCTAssertTrue(read.hasPrefix("AAAA"))
                        }
                    }
                }
            }
        }
    }

    // The launch pattern that crashed: public setters racing payload building on other threads.
    func testPublicSettersRacingDeviceDataDoNotCrash() async {
        let sdk = LinkrunnerSDK.shared
        let token = longToken()
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<12 {
                group.addTask {
                    for round in 0..<200 {
                        switch worker % 4 {
                        case 0:
                            sdk.setConsent(LinkrunnerConsent(
                                isEEA: .granted,
                                hasConsentForDataUsage: round % 2 == 0 ? .granted : .denied,
                                hasConsentForAdsPersonalization: .granted
                            ))
                        case 1:
                            sdk.enablePIIHashing(round % 2 == 0)
                            _ = sdk.isPIIHashingEnabled()
                            sdk.enableTCFConsentCollection(round % 2 == 0)
                        case 2:
                            sdk.cachedAttributionToken = round % 3 == 0 ? nil : token + "\(round)"
                        default:
                            let payload = await sdk.deviceData().toDictionary()
                            XCTAssertNotNil(payload["install_instance_id"])
                        }
                    }
                }
            }
        }
    }

    func testConcurrentSetConsentPersistsTheValueHeldInMemory() async {
        let sdk = LinkrunnerSDK.shared
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for round in 0..<500 {
                        sdk.setConsent(LinkrunnerConsent(
                            isEEA: worker % 2 == 0 ? .granted : .denied,
                            hasConsentForDataUsage: round % 2 == 0 ? .granted : .denied,
                            hasConsentForAdsPersonalization: .unknown
                        ))
                    }
                }
            }
        }
        let inMemory = await sdk.deviceData().consent
        XCTAssertEqual(inMemory, LinkrunnerSDK.loadPersistedConsent())
    }

    func testWithLockMakesCheckThenSetAtomic() async {
        let counter = Synchronized(wrappedValue: 0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    for _ in 0..<5_000 {
                        counter.withLock { $0 += 1 }
                    }
                }
            }
        }
        XCTAssertEqual(counter.wrappedValue, 80_000)
    }

    func testSynchronizedKeepsLastWrite() {
        let box = Synchronized(wrappedValue: "first")
        box.wrappedValue = "second"
        XCTAssertEqual(box.wrappedValue, "second")
    }

    // Shared singletons are called from many threads at once, so every stored `var` on them
    // must be `@Synchronized`. Fails when one is added without it.
    func testSharedSingletonsHaveNoUnguardedStoredVars() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Linkrunner")
        let storedVar = try NSRegularExpression(
            pattern: #"^    (?:@\w+ )*(?:public |private |fileprivate |internal )?(?:static )?var \w+\s*(?::[^{]*)?(?:=.*)?$"#,
            options: .anchorsMatchLines
        )
        for file in ["Linkrunner.swift", "RequestSigningInterceptor.swift"] {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            let unguarded = storedVar.matches(in: text, range: range)
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                .filter { !$0.contains("@Synchronized") }
            XCTAssertEqual(unguarded, [], "\(file) has stored vars without @Synchronized")
        }
    }
}
