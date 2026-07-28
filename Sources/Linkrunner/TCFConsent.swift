import Foundation

/// Derives Google Ads consent from an IAB TCF v2.2/2.3 Consent Management Platform.
///
/// TCF-compliant CMPs write a set of standard keys into `UserDefaults`. Reading them
/// lets an app adopt ICM without threading consent through its own lifecycle, but it is
/// opt-in (`enableTCFConsentCollection`) rather than automatic: interpreting a TC string
/// on the app's behalf is a legal judgement, and the app should agree to it explicitly.
///
/// Mapping follows Google's published TCF integration
/// (https://developers.google.com/tag-platform/security/guides/implement-TCF-strings):
///
///   Purpose 1 denied → ad_storage denied **and** ad_user_data denied
///   Purpose 7 denied → ad_user_data denied
///   Purpose 3 denied → ad_personalization denied
///   Purpose 4 denied → ad_personalization denied
///
/// so `ad_user_data` requires purposes 1 **and** 7, and `ad_personalization` requires
/// purposes 3 **and** 4. Both are additionally gated on vendor consent for Google
/// (TCF vendor ID 755): purpose consent alone is not enough for Google to act as a
/// vendor, so without it we report denied rather than granted.
///
/// Anything the CMP has not written is reported as `.unknown`. That matters on first
/// launch, where the CMP may not have resolved yet — the keys are re-read on every
/// payload rather than snapshotted once, so a later request carries the real answer.
enum TCFConsent {

    // Standard TCF v2.x storage keys. Named by the IAB spec; do not rename.
    private static let gdprAppliesKey = "IABTCF_gdprApplies"
    private static let purposeConsentsKey = "IABTCF_PurposeConsents"
    private static let vendorConsentsKey = "IABTCF_VendorConsents"

    /// Google Advertising Products' vendor ID in the IAB Global Vendor List.
    private static let googleVendorID = 755

    // Google's purpose mapping, as above.
    private static let adUserDataPurposes = [1, 7]
    private static let adPersonalizationPurposes = [3, 4]

    /// Reads current consent from the CMP, or an all-unknown value when no TCF data
    /// is present.
    static func read(from defaults: UserDefaults = .standard) -> LinkrunnerConsent {
        let isUserSubjectToGDPR = readGDPRApplies(from: defaults)

        let purposeConsents = defaults.string(forKey: purposeConsentsKey)
        let vendorConsents = defaults.string(forKey: vendorConsentsKey)

        // Vendor consent for Google gates both signals. Unknown vendor state leaves the
        // signals unknown; explicit vendor denial denies them outright.
        let googleVendorConsent = bit(in: vendorConsents, atOneBasedIndex: googleVendorID)

        return LinkrunnerConsent(
            isUserSubjectToGDPR: isUserSubjectToGDPR,
            hasConsentForDataUsage: resolve(purposes: adUserDataPurposes,
                                in: purposeConsents,
                                vendorConsent: googleVendorConsent),
            hasConsentForAdsPersonalization: resolve(purposes: adPersonalizationPurposes,
                                       in: purposeConsents,
                                       vendorConsent: googleVendorConsent)
        )
    }

    // MARK: - Private

    /// `IABTCF_gdprApplies` is specified as an integer, but CMPs have been observed
    /// storing it as `NSNumber`, `Bool` or a string, so all three are accepted.
    private static func readGDPRApplies(from defaults: UserDefaults) -> ConsentStatus {
        guard let raw = defaults.object(forKey: gdprAppliesKey) else { return .unknown }

        if let number = raw as? NSNumber {
            return number.intValue == 1 ? .granted : .denied
        }
        if let string = raw as? String {
            switch string {
            case "1": return .granted
            case "0": return .denied
            default: return .unknown
            }
        }
        return .unknown
    }

    /// All listed purposes must be granted, and Google must be a consented vendor.
    /// Any missing input yields `.unknown` — never `.granted`.
    private static func resolve(
        purposes: [Int],
        in purposeConsents: String?,
        vendorConsent: Bool?
    ) -> ConsentStatus {
        // An explicit vendor denial is decisive regardless of purposes.
        if vendorConsent == false { return .denied }

        var sawDenial = false
        for purpose in purposes {
            switch bit(in: purposeConsents, atOneBasedIndex: purpose) {
            case .some(true):
                continue
            case .some(false):
                sawDenial = true
            case nil:
                // Purpose absent from the string: we cannot claim consent.
                return .unknown
            }
        }
        if sawDenial { return .denied }

        // Purposes are all granted; require vendor consent to be positively known.
        return vendorConsent == true ? .granted : .unknown
    }

    /// TCF binary strings are 1-indexed by purpose/vendor ID, one ASCII '0' or '1' each.
    /// Returns nil when the string is absent, too short, or holds an unexpected byte.
    private static func bit(in binaryString: String?, atOneBasedIndex index: Int) -> Bool? {
        guard let binaryString = binaryString, index >= 1 else { return nil }

        let scalars = Array(binaryString.utf8)
        let offset = index - 1
        guard offset < scalars.count else { return nil }

        switch scalars[offset] {
        case UInt8(ascii: "1"): return true
        case UInt8(ascii: "0"): return false
        default: return nil
        }
    }
}
