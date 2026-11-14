import XCTest
@testable import LinkrunnerKit

/// Privacy mode must keep every device-level identifier out of the payload and must
/// survive a relaunch, because `deviceData()` can run before `initialize` passes it again.
final class PrivacyModeTests: XCTestCase {

    private var storedValue: Any?

    override func setUp() {
        super.setUp()
        storedValue = UserDefaults.standard.object(forKey: LinkrunnerSDK.PRIVACY_MODE_KEY)
    }

    override func tearDown() {
        // The SDK is a singleton backed by standard defaults; leave both as we found them.
        if let storedValue = storedValue {
            UserDefaults.standard.set(storedValue, forKey: LinkrunnerSDK.PRIVACY_MODE_KEY)
        } else {
            UserDefaults.standard.removeObject(forKey: LinkrunnerSDK.PRIVACY_MODE_KEY)
        }
        LinkrunnerSDK.shared.setPrivacyMode(UserDefaults.standard.bool(forKey: LinkrunnerSDK.PRIVACY_MODE_KEY))
        super.tearDown()
    }

    func testPrivacyModeDropsDeviceIdentifiers() async {
        LinkrunnerSDK.shared.setPrivacyMode(true)

        let data = await LinkrunnerSDK.shared.deviceData()
        let dict = data.toDictionary()

        XCTAssertNil(dict["idfa"])
        XCTAssertNil(dict["idfv"])
        XCTAssertNil(dict["odm_info"])
        XCTAssertEqual(dict["device_name"] as? String, data.device, "device name falls back to the generic model")
        XCTAssertEqual(dict["privacy_mode"] as? Bool, true)
        XCTAssertFalse(data.installInstanceId.isEmpty, "install instance ID is still sent")
    }

    func testIdfvSentWithoutPrivacyMode() async throws {
        #if canImport(UIKit)
        LinkrunnerSDK.shared.setPrivacyMode(false)

        let dict = await LinkrunnerSDK.shared.deviceData().toDictionary()

        XCTAssertNotNil(dict["idfv"])
        XCTAssertNil(dict["privacy_mode"])
        #else
        throw XCTSkip("IDFV only exists on UIKit platforms")
        #endif
    }

    func testPrivacyModeIsPersisted() {
        LinkrunnerSDK.shared.setPrivacyMode(true)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: LinkrunnerSDK.PRIVACY_MODE_KEY))
        XCTAssertTrue(LinkrunnerSDK.shared.isPrivacyModeEnabled())

        LinkrunnerSDK.shared.setPrivacyMode(false)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: LinkrunnerSDK.PRIVACY_MODE_KEY))
        XCTAssertFalse(LinkrunnerSDK.shared.isPrivacyModeEnabled())
    }
}
