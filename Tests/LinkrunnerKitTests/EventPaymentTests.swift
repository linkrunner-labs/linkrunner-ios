import XCTest
@testable import LinkrunnerKit

final class EventPaymentTests: XCTestCase {

    func testAcceptsValidPaymentUppercasesCurrencyAndDefaultsToCompleted() throws {
        let payment = try EventPayment(amount: 499, paymentId: "ord_1", currency: " inr ", userId: "user_1")

        XCTAssertEqual(payment.currency, "INR")
        XCTAssertEqual(payment.userId, "user_1")
        XCTAssertEqual(payment.status, .completed)
    }

    func testAcceptsZeroAmountAndEmptyUserId() {
        XCTAssertNoThrow(try EventPayment(amount: 0, paymentId: "ord_1", currency: "USD", userId: ""))
    }

    func testRejectsInvalidAmount() {
        for amount in [-1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try EventPayment(amount: amount, paymentId: "ord_1", currency: "USD", userId: "u")) {
                XCTAssertEqual($0 as? EventPaymentError, .invalidAmount)
            }
        }
    }

    func testRejectsBlankPaymentId() {
        for paymentId in ["", "   "] {
            XCTAssertThrowsError(try EventPayment(amount: 1, paymentId: paymentId, currency: "USD", userId: "u")) {
                XCTAssertEqual($0 as? EventPaymentError, .invalidPaymentId)
            }
        }
    }

    func testRejectsInvalidCurrency() {
        for currency in ["", "US", "USDT", "U5D", "ÜSD"] {
            XCTAssertThrowsError(try EventPayment(amount: 1, paymentId: "ord_1", currency: currency, userId: "u")) {
                XCTAssertEqual($0 as? EventPaymentError, .invalidCurrency)
            }
        }
    }

    func testRequestFieldsCarryUserIdAndDefaultStatus() throws {
        let fields = try EventPayment(amount: 10, paymentId: "ord_1", currency: "usd", userId: "user_1").requestFields

        XCTAssertEqual(Set(fields.keys), ["amount", "payment_id", "currency", "status", "user_id"])
        XCTAssertEqual(fields["amount"] as? Double, 10)
        XCTAssertEqual(fields["payment_id"] as? String, "ord_1")
        XCTAssertEqual(fields["currency"] as? String, "USD")
        XCTAssertEqual(fields["status"] as? String, "PAYMENT_COMPLETED")
        XCTAssertEqual(fields["user_id"] as? String, "user_1")
    }

    func testRequestFieldsLeaveUserIdOutWhenEmptySoTheSavedUserIsUsed() throws {
        let fields = try EventPayment(amount: 1, paymentId: "ord_1", currency: "USD", userId: "", status: .failed).requestFields

        XCTAssertNil(fields["user_id"])
        XCTAssertEqual(fields["status"] as? String, "PAYMENT_FAILED")
    }
}
