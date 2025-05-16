import XCTest
@testable import Linkrunner

final class LinkrunnerTests: XCTestCase {
    
    func testLinkrunnerInitialization() {
        let linkrunner = Linkrunner.shared
        XCTAssertNotNil(linkrunner)
    }
    
    func testUserDataDictionary() {
        let userData = UserData(
            id: "test-user-123",
            name: "Test User",
            phone: "1234567890",
            email: "test@example.com"
        )
        
        let dict = userData.dictionary
        
        XCTAssertEqual(dict["id"] as? String, "test-user-123")
        XCTAssertEqual(dict["name"] as? String, "Test User")
        XCTAssertEqual(dict["phone"] as? String, "1234567890")
        XCTAssertEqual(dict["email"] as? String, "test@example.com")
    }
    
    func testPaymentTypeRawValues() {
        XCTAssertEqual(PaymentType.firstPayment.rawValue, "FIRST_PAYMENT")
        XCTAssertEqual(PaymentType.walletTopup.rawValue, "WALLET_TOPUP")
        XCTAssertEqual(PaymentType.fundsWithdrawal.rawValue, "FUNDS_WITHDRAWAL")
        XCTAssertEqual(PaymentType.subscriptionCreated.rawValue, "SUBSCRIPTION_CREATED")
        XCTAssertEqual(PaymentType.subscriptionRenewed.rawValue, "SUBSCRIPTION_RENEWED")
        XCTAssertEqual(PaymentType.oneTime.rawValue, "ONE_TIME")
        XCTAssertEqual(PaymentType.recurring.rawValue, "RECURRING")
        XCTAssertEqual(PaymentType.default.rawValue, "DEFAULT")
    }
    
    func testPaymentStatusRawValues() {
        XCTAssertEqual(PaymentStatus.initiated.rawValue, "PAYMENT_INITIATED")
        XCTAssertEqual(PaymentStatus.completed.rawValue, "PAYMENT_COMPLETED")
        XCTAssertEqual(PaymentStatus.failed.rawValue, "PAYMENT_FAILED")
        XCTAssertEqual(PaymentStatus.cancelled.rawValue, "PAYMENT_CANCELLED")
    }
}
