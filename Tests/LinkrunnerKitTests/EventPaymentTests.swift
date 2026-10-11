import XCTest
@testable import LinkrunnerKit

final class EventPaymentTests: XCTestCase {

    func testAcceptsValidPaymentAndUppercasesCurrency() throws {
        let payment = try EventPayment(amount: 499, paymentId: "ord_1", currency: " inr ")

        XCTAssertEqual(payment.currency, "INR")
        XCTAssertNil(payment.status)
    }

    func testAcceptsZeroAmount() {
        XCTAssertNoThrow(try EventPayment(amount: 0, paymentId: "ord_1", currency: "USD"))
    }

    func testRejectsInvalidAmount() {
        for amount in [-1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try EventPayment(amount: amount, paymentId: "ord_1", currency: "USD")) {
                XCTAssertEqual($0 as? EventPaymentError, .invalidAmount)
            }
        }
    }

    func testRejectsBlankPaymentId() {
        for paymentId in ["", "   "] {
            XCTAssertThrowsError(try EventPayment(amount: 1, paymentId: paymentId, currency: "USD")) {
                XCTAssertEqual($0 as? EventPaymentError, .invalidPaymentId)
            }
        }
    }

    func testRejectsInvalidCurrency() {
        for currency in ["", "US", "USDT", "U5D", "ÜSD"] {
            XCTAssertThrowsError(try EventPayment(amount: 1, paymentId: "ord_1", currency: currency)) {
                XCTAssertEqual($0 as? EventPaymentError, .invalidCurrency)
            }
        }
    }

    func testRequestFieldsLeaveStatusOutWhenNotSet() throws {
        let fields = try EventPayment(amount: 10, paymentId: "ord_1", currency: "usd").requestFields

        XCTAssertEqual(Set(fields.keys), ["amount", "payment_id", "currency"])
        XCTAssertEqual(fields["amount"] as? Double, 10)
        XCTAssertEqual(fields["payment_id"] as? String, "ord_1")
        XCTAssertEqual(fields["currency"] as? String, "USD")
    }

    func testRequestFieldsSendStatusWhenSet() throws {
        let fields = try EventPayment(amount: 1, paymentId: "ord_1", currency: "USD", status: .failed).requestFields

        XCTAssertEqual(fields["status"] as? String, "PAYMENT_FAILED")
    }
}
