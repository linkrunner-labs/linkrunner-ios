import XCTest
@testable import LinkrunnerKit

/// Covers `ODMService` when Google's ODM SDK is **not** linked into the app.
///
/// This is the path most apps take: LinkrunnerKit has no build-time dependency on
/// `GoogleAdsOnDeviceConversion`, so unless the host app adds it, every entry point
/// must degrade to a silent no-op rather than crashing or blocking.
///
/// The test bundle does not link Google's SDK, so `NSClassFromString` returns nil here
/// and these exercise the real absent-path code rather than a stub.
@available(iOS 15.0, *)
final class ODMServiceAbsentSDKTests: XCTestCase {

    private let installInstanceId = "test-install-instance"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "linkrunner_odm_info_\(installInstanceId)")
        UserDefaults.standard.removeObject(forKey: "linkrunner_odm_current_key")
        super.tearDown()
    }

    func testGoogleSDKIsGenuinelyAbsentInThisBundle() {
        // Guards the premise of every other test in this class. If Google's SDK ever
        // gets linked into the test target, these tests stop testing what they claim to.
        XCTAssertNil(NSClassFromString("ODCConversionManager"),
                     "test bundle must not link GoogleAdsOnDeviceConversion")
    }

    func testIsAvailableIsFalseWithoutTheSDK() {
        XCTAssertFalse(ODMService.shared.isAvailable)
    }

    func testSetFirstLaunchTimeIsANoOpAndDoesNotCrash() {
        // No assertion beyond "returns normally" — the point is that a missing class
        // must not produce an unrecognised-selector crash in the host app.
        ODMService.shared.setFirstLaunchTime(Date())
    }

    func testResolveInfoReportsUnavailableAndReturnsNoValue() async {
        let (info, diagnostics) = await ODMService.shared.resolveInfo(
            installInstanceId: installInstanceId,
            timeout: 5.0
        )

        XCTAssertNil(info)
        XCTAssertFalse(diagnostics.available)
        XCTAssertEqual(diagnostics.result, .unavailable)
    }

    func testResolveInfoReturnsImmediatelyRatherThanWaitingOutTheTimeout() async {
        // An absent SDK must short-circuit before the timeout race starts, otherwise
        // every launch of every non-ICM app would pay the full timeout.
        let start = Date()
        _ = await ODMService.shared.resolveInfo(installInstanceId: installInstanceId, timeout: 5.0)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "absent SDK must not block for the timeout duration")
    }

    func testCachedValueIsReturnedEvenWhenTheSDKIsAbsent() async {
        // A value cached while the SDK was present must still be sent afterwards —
        // e.g. the app kept the cached odm_info but a later build dropped the framework.
        let key = "linkrunner_odm_info_\(installInstanceId)"
        UserDefaults.standard.set("cached-odm-value", forKey: key)

        let (info, diagnostics) = await ODMService.shared.resolveInfo(
            installInstanceId: installInstanceId,
            timeout: 5.0
        )

        XCTAssertEqual(info, "cached-odm-value")
        XCTAssertTrue(diagnostics.available)
        XCTAssertEqual(diagnostics.result, .success)
    }

    func testEmptyCachedValueIsIgnored() async {
        UserDefaults.standard.set("", forKey: "linkrunner_odm_info_\(installInstanceId)")

        let (info, diagnostics) = await ODMService.shared.resolveInfo(
            installInstanceId: installInstanceId,
            timeout: 5.0
        )

        XCTAssertNil(info, "an empty cached value must not be treated as a real one")
        XCTAssertEqual(diagnostics.result, .unavailable)
    }

    func testCacheIsScopedToInstallInstance() async {
        UserDefaults.standard.set("value-for-other-install",
                                  forKey: "linkrunner_odm_info_a-different-install")

        let (info, _) = await ODMService.shared.resolveInfo(
            installInstanceId: installInstanceId,
            timeout: 5.0
        )

        XCTAssertNil(info, "another install instance's value must never be reused")
        UserDefaults.standard.removeObject(forKey: "linkrunner_odm_info_a-different-install")
    }
}
