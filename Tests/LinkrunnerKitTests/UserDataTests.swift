import XCTest
@testable import LinkrunnerKit

/// LIN-3534: `setUserData` can be called right after `initialize`, before the app knows
/// its customer user id, with only analytics ids.
final class UserDataTests: XCTestCase {

    func testIdLessUserDataOmitsId() {
        let dict = UserData(mixPanelDistinctId: "mp-1", moengageUserId: "moe-1").toDictionary()

        XCTAssertNil(dict["id"])
        XCTAssertEqual(dict["mixpanel_distinct_id"] as? String, "mp-1")
        XCTAssertEqual(dict["moengage_user_id"] as? String, "moe-1")
    }

    func testEmptyIdIsTreatedAsAbsent() {
        let userData = UserData(id: "", posthogDistinctId: "ph-1")

        XCTAssertNil(userData.customerUserId)
        XCTAssertNil(userData.toDictionary()["id"])
    }

    func testIdIsSentWhenPresent() {
        let userData = UserData(id: "user-1", name: "Priya")

        XCTAssertEqual(userData.customerUserId, "user-1")
        XCTAssertEqual(userData.toDictionary()["id"] as? String, "user-1")
        XCTAssertEqual(userData.toDictionary()["name"] as? String, "Priya")
    }
}
