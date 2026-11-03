import XCTest
@testable import LinkrunnerKit

@available(*, deprecated)
final class DeprecatedPaymentAPITests: XCTestCase {
    func testPaymentTypeRawValuesMatchOldTypes() {
        XCTAssertEqual(PaymentType.firstPayment.rawValue, "FIRST_PAYMENT")
        XCTAssertEqual(PaymentType.default.rawValue, "DEFAULT")
        XCTAssertEqual(PaymentType.subscriptionRenewed.rawValue, "SUBSCRIPTION_RENEWED")
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    func testDeprecatedPaymentCallsDoNothingBeforeInit() async {
        await LinkrunnerSDK.shared.capturePayment(amount: 1, userId: "u1", paymentId: "p1", type: .firstPayment, status: .completed)
        await LinkrunnerSDK.shared.removePayment(userId: "u1", paymentId: "p1")
    }
}
