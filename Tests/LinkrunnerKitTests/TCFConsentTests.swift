import XCTest
@testable import LinkrunnerKit

/// Covers the IAB TCF → Google Ads consent mapping.
///
/// The invariant these tests exist to protect: **every missing, truncated or malformed
/// input must resolve to `.unknown`, never `.granted`.** A false `.granted` misstates a
/// user's legal choice to Google, which is a materially worse failure than reporting
/// nothing at all.
///
/// Mapping under test (Google's published TCF integration):
///   ad_user_data        ← purposes 1 AND 7
///   ad_personalization  ← purposes 3 AND 4
///   both additionally gated on vendor consent for Google (TCF vendor 755)
final class TCFConsentTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    private static let googleVendorID = 755

    override func setUp() {
        super.setUp()
        suiteName = "io.linkrunner.tests.tcf.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// TCF binary strings are 1-indexed, one ASCII '0'/'1' per purpose or vendor ID.
    private func binaryString(granted: Set<Int>, length: Int) -> String {
        String((1...length).map { granted.contains($0) ? Character("1") : Character("0") })
    }

    private func writeCMP(gdprApplies: Any? = nil, purposes: Set<Int>? = nil, vendors: Set<Int>? = nil) {
        if let gdprApplies = gdprApplies {
            defaults.set(gdprApplies, forKey: "IABTCF_gdprApplies")
        }
        if let purposes = purposes {
            defaults.set(binaryString(granted: purposes, length: 10), forKey: "IABTCF_PurposeConsents")
        }
        if let vendors = vendors {
            defaults.set(binaryString(granted: vendors, length: Self.googleVendorID + 1),
                         forKey: "IABTCF_VendorConsents")
        }
    }

    // MARK: - No CMP present

    func testNoTCFDataResolvesEverythingUnknown() {
        let consent = TCFConsent.read(from: defaults)

        XCTAssertEqual(consent.isUserSubjectToGDPR, .unknown)
        XCTAssertEqual(consent.hasConsentForDataUsage, .unknown)
        XCTAssertEqual(consent.hasConsentForAdsPersonalization, .unknown)
    }

    func testAllUnknownConsentIsOmittedFromPayload() {
        let consent = TCFConsent.read(from: defaults)

        XCTAssertTrue(consent.isEmpty, "an all-unknown consent must drop the key entirely")
        XCTAssertTrue(consent.toDictionary().isEmpty)
    }

    // MARK: - Full consent

    func testFullConsentInEEA() {
        writeCMP(gdprApplies: 1, purposes: [1, 3, 4, 7], vendors: [Self.googleVendorID])

        let consent = TCFConsent.read(from: defaults)

        XCTAssertEqual(consent.isUserSubjectToGDPR, .granted)
        XCTAssertEqual(consent.hasConsentForDataUsage, .granted)
        XCTAssertEqual(consent.hasConsentForAdsPersonalization, .granted)
    }

    // MARK: - Purpose mapping

    func testPurpose1DeniedDeniesDataUsageOnly() {
        writeCMP(gdprApplies: 1, purposes: [3, 4, 7], vendors: [Self.googleVendorID])

        let consent = TCFConsent.read(from: defaults)

        XCTAssertEqual(consent.hasConsentForDataUsage, .denied)
        XCTAssertEqual(consent.hasConsentForAdsPersonalization, .granted,
                       "purpose 1 must not affect ad_personalization")
    }

    func testPurpose7DeniedDeniesDataUsage() {
        writeCMP(purposes: [1, 3, 4], vendors: [Self.googleVendorID])

        XCTAssertEqual(TCFConsent.read(from: defaults).hasConsentForDataUsage, .denied)
    }

    func testPurpose3DeniedDeniesPersonalization() {
        writeCMP(purposes: [1, 4, 7], vendors: [Self.googleVendorID])

        XCTAssertEqual(TCFConsent.read(from: defaults).hasConsentForAdsPersonalization, .denied)
    }

    func testPurpose4DeniedDeniesPersonalizationOnly() {
        writeCMP(gdprApplies: 1, purposes: [1, 3, 7], vendors: [Self.googleVendorID])

        let consent = TCFConsent.read(from: defaults)

        XCTAssertEqual(consent.hasConsentForAdsPersonalization, .denied)
        XCTAssertEqual(consent.hasConsentForDataUsage, .granted,
                       "purpose 4 must not affect ad_user_data")
    }

    // MARK: - Vendor gating

    func testGoogleVendorDeniedDeniesBothDespiteFullPurposeConsent() {
        writeCMP(gdprApplies: 1, purposes: [1, 3, 4, 7], vendors: [])

        let consent = TCFConsent.read(from: defaults)

        XCTAssertEqual(consent.hasConsentForDataUsage, .denied)
        XCTAssertEqual(consent.hasConsentForAdsPersonalization, .denied)
    }

    func testAbsentVendorStringYieldsUnknownNotGranted() {
        writeCMP(gdprApplies: 1, purposes: [1, 3, 4, 7])

        let consent = TCFConsent.read(from: defaults)

        XCTAssertEqual(consent.hasConsentForDataUsage, .unknown)
        XCTAssertEqual(consent.hasConsentForAdsPersonalization, .unknown)
    }

    func testVendorStringTooShortToCoverGoogleYieldsUnknown() {
        defaults.set(binaryString(granted: [1, 3, 4, 7], length: 10), forKey: "IABTCF_PurposeConsents")
        // Stops well before index 755.
        defaults.set(binaryString(granted: [1], length: 100), forKey: "IABTCF_VendorConsents")

        XCTAssertEqual(TCFConsent.read(from: defaults).hasConsentForDataUsage, .unknown)
    }

    // MARK: - Malformed input

    func testPurposeStringTruncatedBeforePurpose7YieldsUnknown() {
        defaults.set(binaryString(granted: [1, 3, 4], length: 4), forKey: "IABTCF_PurposeConsents")
        defaults.set(binaryString(granted: [Self.googleVendorID], length: Self.googleVendorID + 1),
                     forKey: "IABTCF_VendorConsents")

        let consent = TCFConsent.read(from: defaults)

        XCTAssertEqual(consent.hasConsentForDataUsage, .unknown,
                       "purpose 7 is past the end of the string, so consent is not knowable")
        XCTAssertEqual(consent.hasConsentForAdsPersonalization, .granted)
    }

    func testUnexpectedCharacterInPurposeStringYieldsUnknown() {
        defaults.set("1X111117", forKey: "IABTCF_PurposeConsents")
        defaults.set(binaryString(granted: [Self.googleVendorID], length: Self.googleVendorID + 1),
                     forKey: "IABTCF_VendorConsents")

        // Purpose 3 is 'X' — unparseable, so personalization cannot be claimed.
        XCTAssertEqual(TCFConsent.read(from: defaults).hasConsentForAdsPersonalization, .unknown)
    }

    func testEmptyPurposeStringYieldsUnknown() {
        defaults.set("", forKey: "IABTCF_PurposeConsents")

        XCTAssertEqual(TCFConsent.read(from: defaults).hasConsentForDataUsage, .unknown)
    }

    // MARK: - gdprApplies encodings

    func testGDPRAppliesZeroMeansNotSubject() {
        writeCMP(gdprApplies: 0)

        XCTAssertEqual(TCFConsent.read(from: defaults).isUserSubjectToGDPR, .denied)
    }

    func testGDPRAppliesAcceptsStringEncoding() {
        // Some CMPs store this as a string rather than the specified integer.
        writeCMP(gdprApplies: "1")

        XCTAssertEqual(TCFConsent.read(from: defaults).isUserSubjectToGDPR, .granted)
    }

    func testGDPRAppliesUnrecognizedValueYieldsUnknown() {
        writeCMP(gdprApplies: "maybe")

        XCTAssertEqual(TCFConsent.read(from: defaults).isUserSubjectToGDPR, .unknown)
    }

    // MARK: - Serialization

    func testUnknownSignalsAreOmittedRatherThanSentAsDenied() {
        let consent = LinkrunnerConsent(
            isUserSubjectToGDPR: .granted,
            hasConsentForDataUsage: .denied,
            hasConsentForAdsPersonalization: .unknown
        )

        let dict = consent.toDictionary()

        XCTAssertEqual(dict["is_eea"] as? String, "1")
        XCTAssertEqual(dict["ad_user_data"] as? String, "0")
        XCTAssertNil(dict["ad_personalization"],
                     "unknown must be absent, so the backend can tell it from a denial")
    }
}
