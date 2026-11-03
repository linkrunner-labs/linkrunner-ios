import XCTest
@testable import LinkrunnerKit

final class InAppPaymentTests: XCTestCase {

    private let payment: SendableDictionary = ["amount": 1200, "paymentId": "bk_1", "currency": "INR", "userId": "u1"]

    private func failure(_ data: SendableDictionary) -> InAppPayment.Failure? {
        if case .failure(let failure) = InAppPayment.extract(data) { return failure }
        return nil
    }

    private func extracted(_ data: SendableDictionary) throws -> (payment: InAppPayment?, eventData: SendableDictionary?) {
        try InAppPayment.extract(data).get()
    }

    func testEventDataWithoutPaymentIdIsACustomEventAndIsLeftUntouched() throws {
        let split = try extracted(["amount": 10, "currency": "INR", "status": "x", "userId": "u9"])

        XCTAssertNil(split.payment)
        XCTAssertEqual(split.eventData?.count, 4)
        XCTAssertEqual(split.eventData?["status"] as? String, "x")
        XCTAssertNil(try InAppPayment.extract(nil).get().payment)
    }

    func testFullPaymentIsExtractedAndItsKeysAreRemoved() throws {
        var data = payment
        data["venue"] = "v_1"
        let split = try extracted(data)

        XCTAssertEqual(split.payment, InAppPayment(amount: 1200, paymentId: "bk_1", currency: "INR", userId: "u1", status: .completed))
        XCTAssertEqual(split.eventData?.keys.sorted(), ["venue"])
    }

    func testPaymentWithOnlyPaymentKeysHasNoEventData() throws {
        XCTAssertNil(try extracted(payment).eventData)
    }

    func testStatusAcceptsTheEnumAndItsExactName() throws {
        var data = payment
        data["status"] = PaymentStatus.cancelled
        XCTAssertEqual(try extracted(data).payment?.status, .cancelled)
        data["status"] = "PAYMENT_FAILED"
        XCTAssertEqual(try extracted(data).payment?.status, .failed)
    }

    func testCurrencyIsTrimmedAndUppercased() throws {
        var data = payment
        data["currency"] = " usd "
        XCTAssertEqual(try extracted(data).payment?.currency, "USD")
    }

    func testPaymentIdWithoutAmountOrCurrencyFails() {
        for key in ["amount", "currency"] {
            var data = payment
            data.removeValue(forKey: key)
            XCTAssertEqual(failure(data), .incomplete, key)
            XCTAssertEqual(failure(data)?.description, "amount, paymentId and currency must be sent together")
        }
    }

    func testInvalidPaymentFieldsFail() {
        let cases: [(String, Any, InAppPayment.Failure)] = [
            ("amount", -1, .invalidAmount),
            ("amount", "12", .invalidAmount),
            ("amount", true, .invalidAmount),
            ("amount", Double.nan, .invalidAmount),
            ("paymentId", " ", .invalidPaymentId),
            ("paymentId", 42, .invalidPaymentId),
            ("currency", "US", .invalidCurrency),
            ("status", "payment_completed", .invalidStatus),
            ("status", 3, .invalidStatus),
        ]
        for (key, value, expected) in cases {
            var data = payment
            data[key] = value
            XCTAssertEqual(failure(data), expected, "\(key)=\(value)")
        }
        var noUser = payment
        noUser.removeValue(forKey: "userId")
        XCTAssertEqual(failure(noUser), .missingUserId)
    }

    func testRequestFieldsCarryThePaymentAndSkipABlankUserId() throws {
        var data = payment
        data["userId"] = ""
        let fields = try XCTUnwrap(try extracted(data).payment).requestFields

        XCTAssertEqual(fields["amount"] as? Double, 1200)
        XCTAssertEqual(fields["payment_id"] as? String, "bk_1")
        XCTAssertEqual(fields["currency"] as? String, "INR")
        XCTAssertEqual(fields["status"] as? String, "PAYMENT_COMPLETED")
        XCTAssertNil(fields["user_id"])
    }
}
