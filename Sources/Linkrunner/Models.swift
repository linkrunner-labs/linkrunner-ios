import Foundation

// MARK: - Error Types

public enum LinkrunnerError: Error {
    case notInitialized
    case invalidUrl
    case httpError(Int)
    case apiError(String)
    case jsonEncodingFailed
    case jsonDecodingFailed
    case invalidResponse
    case invalidParameters(String)
}

extension LinkrunnerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Linkrunner not initialized. Call initialize(token:) first."
        case .invalidUrl:
            return "Invalid URL"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .jsonEncodingFailed:
            return "Failed to encode JSON"
        case .jsonDecodingFailed:
            return "Failed to decode JSON"
        case .invalidResponse:
            return "Invalid API response"
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        }
    }
}

// Sendable dictionary type alias
public typealias SendableDictionary = [String: Any] 
extension SendableDictionary: @unchecked Sendable {}

// MARK: - Consent

/// Tri-state consent signal for Google Ads.
///
/// `unknown` is a distinct state, not a synonym for `denied` or `granted`. Google's
/// App Conversion API treats the consent parameters as "required to be sent when the
/// value is known", so an unknown value is omitted from the request rather than
/// guessed. Never map `unknown` to `granted`.
public enum ConsentStatus: String, Sendable {
    /// The user gave consent. Sent to Google as `1`.
    case granted
    /// The user refused consent. Sent to Google as `0`.
    case denied
    /// You do not know the user's choice — they have not been asked yet, your CMP has
    /// not resolved, or the signal does not apply. **Omitted from the request entirely**,
    /// so Google can tell "we were never told" apart from "the user said no".
    ///
    /// This is the default. Leaving a signal `unknown` is always safer than guessing.
    case unknown

    /// Wire form: `"1"`, `"0"`, or `nil` when unknown (the parameter is then omitted).
    var wireValue: String? {
        switch self {
        case .granted: return "1"
        case .denied: return "0"
        case .unknown: return nil
        }
    }
}

/// Google Ads consent state, normally sourced from your Consent Management Platform.
///
/// Set it with `LinkrunnerSDK.shared.setConsent(_:)` before `initialize`, and call the
/// same method again whenever your CMP state changes. Defaults to all-`unknown`,
/// which is reported honestly rather than assumed permissive.
///
/// ATT authorization is *not* equivalent to either of these signals — it governs
/// IDFA access, not Google's use of ad user data or personalization. The SDK reports
/// ATT status separately.
public struct LinkrunnerConsent: Sendable, Equatable {
    /// Whether European regulations apply to this user, sent to Google as `is_eea`.
    ///
    /// Despite the name, this is **broader than the EEA and broader than GDPR**. Google
    /// defines the parameter as "European regulations apply to this user and
    /// conversion", which covers GDPR (EEA), UK GDPR, the Swiss FADP and the DMA. Set it
    /// `.granted` for users in the **EEA, the United Kingdom or Switzerland** — a UK user
    /// is subject to UK GDPR rather than GDPR, and a Swiss user to the FADP, but both are
    /// in scope here. That population is also exactly the scope of Integrated Conversion
    /// Measurement, so getting this wrong silently excludes the users ICM exists for.
    ///
    /// The name mirrors the wire key and Google's own `eea` parameter.
    public let isEEA: ConsentStatus
    /// Whether the user consented to their data being **sent to Google** for advertising
    /// purposes. Sent as `ad_user_data`.
    ///
    /// This governs transmission: may we share this user's data with Google at all.
    /// Without it Google cannot attribute the conversion to a campaign, so a denial
    /// generally means the install is not measurable through Google.
    ///
    /// Typically maps to your CMP's "share data with advertising partners" choice, or
    /// TCF purposes 1 and 7.
    ///
    /// Not the same as ATT: a user can allow tracking at the iOS level and still refuse
    /// this, or vice versa.
    public let hasConsentForDataUsage: ConsentStatus

    /// Whether the user consented to their data being used to **personalize ads**.
    /// Sent as `ad_personalization`.
    ///
    /// This governs use rather than transmission: Google may still measure the
    /// conversion, but may not use the data to build a profile or target ads. Denying
    /// this while granting ``hasConsentForDataUsage`` is a normal, common combination.
    ///
    /// Typically maps to your CMP's "personalized advertising" choice, or TCF
    /// purposes 3 and 4.
    public let hasConsentForAdsPersonalization: ConsentStatus

    /// Creates a consent state to hand to `LinkrunnerSDK.shared.setConsent(_:)`.
    ///
    /// Every parameter defaults to `.unknown`, so you can supply only what you actually
    /// know — omitted signals are left out of the payload rather than guessed at.
    ///
    /// ```swift
    /// LinkrunnerSDK.shared.setConsent(LinkrunnerConsent(
    ///     isEEA: .granted,
    ///     hasConsentForDataUsage: .granted,
    ///     hasConsentForAdsPersonalization: .denied
    /// ))
    /// ```
    ///
    /// - Parameters:
    ///   - isEEA: Whether **European regulations apply** to this user — the EEA, the
    ///     United Kingdom *or* Switzerland. Broader than GDPR alone, and it is exactly
    ///     the population Integrated Conversion Measurement covers. Sent as `is_eea`.
    ///   - hasConsentForDataUsage: Whether the user consented to their data being **sent
    ///     to Google** for advertising. Governs transmission. Sent as `ad_user_data`.
    ///   - hasConsentForAdsPersonalization: Whether the user consented to their data
    ///     being used to **personalize ads**. Governs use, not transmission, so denying
    ///     it while granting data usage is normal. Sent as `ad_personalization`.
    public init(
        isEEA: ConsentStatus = .unknown,
        hasConsentForDataUsage: ConsentStatus = .unknown,
        hasConsentForAdsPersonalization: ConsentStatus = .unknown
    ) {
        self.isEEA = isEEA
        self.hasConsentForDataUsage = hasConsentForDataUsage
        self.hasConsentForAdsPersonalization = hasConsentForAdsPersonalization
    }

    /// Omits any signal that is `unknown`, so the backend can distinguish
    /// "user said no" from "we were never told".
    func toDictionary() -> SendableDictionary {
        var dict: SendableDictionary = [:]
        if let isEEA = isEEA.wireValue { dict["is_eea"] = isEEA }
        if let adUserData = hasConsentForDataUsage.wireValue { dict["ad_user_data"] = adUserData }
        if let adPersonalization = hasConsentForAdsPersonalization.wireValue { dict["ad_personalization"] = adPersonalization }
        return dict
    }

    /// True when nothing is known, in which case the key is dropped entirely.
    var isEmpty: Bool {
        return isEEA == .unknown && hasConsentForDataUsage == .unknown && hasConsentForAdsPersonalization == .unknown
    }
}

// MARK: - Model Types

public struct UserData: Sendable {
    public let id: String
    public let name: String?
    public let phone: String?
    public let email: String?
    public let isFirstTimeUser: Bool?
    public let userCreatedAt: String?
    public let mixPanelDistinctId: String?
    public let amplitudeDeviceId: String?
    public let posthogDistinctId: String?
    public let brazeDeviceId: String?
    public let gaAppInstanceId: String?
    public let gaSessionId: String?
    public let netcoreDeviceGuid: String?
    
    public init(
        id: String,
        name: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        isFirstTimeUser: Bool? = nil,
        userCreatedAt: String? = nil,
        mixPanelDistinctId: String? = nil,
        amplitudeDeviceId: String? = nil,
        posthogDistinctId: String? = nil,
        brazeDeviceId: String? = nil,
        gaAppInstanceId: String? = nil,
        gaSessionId: String? = nil,
        netcoreDeviceGuid: String? = nil
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.isFirstTimeUser = isFirstTimeUser
        self.userCreatedAt = userCreatedAt
        self.mixPanelDistinctId = mixPanelDistinctId
        self.amplitudeDeviceId = amplitudeDeviceId
        self.posthogDistinctId = posthogDistinctId
        self.brazeDeviceId = brazeDeviceId
        self.gaAppInstanceId = gaAppInstanceId
        self.gaSessionId = gaSessionId
        self.netcoreDeviceGuid = netcoreDeviceGuid
    }
    
    /// Converts UserData to a dictionary, optionally hashing PII fields
    /// - Parameter hashPII: Whether to hash PII fields
    /// - Returns: Dictionary representation of UserData
    func toDictionary(hashPII: Bool = false) -> SendableDictionary {
        var dict: SendableDictionary = ["id": id]
        
        if let name = name {
            dict["name"] = hashPII ? LinkrunnerSDK.shared.hashWithSHA256(name) : name
        }
        
        if let phone = phone {
            dict["phone"] = hashPII ? LinkrunnerSDK.shared.hashWithSHA256(phone) : phone
        }
        
        if let email = email {
            dict["email"] = hashPII ? LinkrunnerSDK.shared.hashWithSHA256(email) : email
        }
        
        if let isFirstTimeUser = isFirstTimeUser {
            dict["is_first_time_user"] = isFirstTimeUser
        }
        
        if let userCreatedAt = userCreatedAt {
            dict["user_created_at"] = userCreatedAt
        }
        
        if let mixPanelDistinctId = mixPanelDistinctId {
            dict["mixpanel_distinct_id"] = mixPanelDistinctId
        }
        
        if let amplitudeDeviceId = amplitudeDeviceId {
            dict["amplitude_device_id"] = amplitudeDeviceId
        }
        
        if let posthogDistinctId = posthogDistinctId {
            dict["posthog_distinct_id"] = posthogDistinctId
        }

        if let brazeDeviceId = brazeDeviceId {
            dict["braze_device_id"] = brazeDeviceId
        }
        
        if let gaAppInstanceId = gaAppInstanceId {
            dict["ga_app_instance_id"] = gaAppInstanceId
        }

        if let gaSessionId = gaSessionId {
            dict["ga_session_id"] = gaSessionId
        }
        
        if let netcoreDeviceGuid = netcoreDeviceGuid {
            dict["netcore_device_guid"] = netcoreDeviceGuid
        }
        
        return dict
    }
    
    /// Legacy dictionary property for backward compatibility
    var dictionary: SendableDictionary {
        return toDictionary(hashPII: false)
    }
}

public struct CampaignData: Codable, Sendable {
    public let id: String
    public let name: String
    public let type: CampaignType
    public let adNetwork: AdNetwork?
    public let groupName: String?
    public let assetGroupName: String?
    public let adNetworkCampaignId: String?
    public let adSetId: String?
    public let adSetName: String?
    public let adCreativeId: String?
    public let adCreativeName: String?
    public let assetName: String?
    public let installedAt: Date?
    public let storeClickAt: Date?
    
    public enum CampaignType: String, Codable, Sendable {
        case organic = "ORGANIC"
        case inorganic = "INORGANIC"
    }
    
    public enum AdNetwork: String, Codable, Sendable {
        case meta = "META"
        case google = "GOOGLE"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, type
        case adNetwork = "ad_network"
        case groupName = "group_name"
        case assetGroupName = "asset_group_name"
        case adNetworkCampaignId = "ad_network_campaign_id"
        case adSetId = "ad_set_id"
        case adSetName = "ad_set_name"
        case adCreativeId = "ad_creative_id"
        case adCreativeName = "ad_creative_name"
        case assetName = "asset_name"
        case installedAt = "installed_at"
        case storeClickAt = "store_click_at"
    }
    
    init(dictionary: SendableDictionary) throws {
        guard let id = dictionary["id"] as? String,
              let name = dictionary["name"] as? String,
              let type = dictionary["type"] as? String else {
            throw LinkrunnerError.invalidResponse
        }
        
        self.id = id
        self.name = name
        self.type = CampaignType(rawValue: type) ?? .organic
        self.adNetwork = (dictionary["ad_network"] as? String).flatMap { AdNetwork(rawValue: $0) }
        self.groupName = dictionary["group_name"] as? String
        self.assetGroupName = dictionary["asset_group_name"] as? String
        self.adNetworkCampaignId = dictionary["ad_network_campaign_id"] as? String
        self.adSetId = dictionary["ad_set_id"] as? String
        self.adSetName = dictionary["ad_set_name"] as? String
        self.adCreativeId = dictionary["ad_creative_id"] as? String
        self.adCreativeName = dictionary["ad_creative_name"] as? String
        self.assetName = dictionary["asset_name"] as? String
        
        // Parse date strings
        let dateFormatter = ISO8601DateFormatter()
        
        if let installedAtString = dictionary["installed_at"] as? String, installedAtString != "<null>" {
            self.installedAt = dateFormatter.date(from: installedAtString)
        } else {
            self.installedAt = nil
        }
        
        if let storeClickAtString = dictionary["store_click_at"] as? String, storeClickAtString != "<null>" {
            self.storeClickAt = dateFormatter.date(from: storeClickAtString)
        } else {
            self.storeClickAt = nil
        }
    }


    public func toDictionary() -> SendableDictionary {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        var dict: SendableDictionary = [
            "id": id,
            "name": name,
            "type": type.rawValue
        ]
        
        if let adNetwork = adNetwork {
            dict["ad_network"] = adNetwork.rawValue
        }
        
        if let groupName = groupName {
            dict["group_name"] = groupName
        }
        
        if let assetGroupName = assetGroupName {
            dict["asset_group_name"] = assetGroupName
        }

        if let adNetworkCampaignId = adNetworkCampaignId {
            dict["ad_network_campaign_id"] = adNetworkCampaignId
        }

        if let adSetId = adSetId {
            dict["ad_set_id"] = adSetId
        }

        if let adSetName = adSetName {
            dict["ad_set_name"] = adSetName
        }

        if let adCreativeId = adCreativeId {
            dict["ad_creative_id"] = adCreativeId
        }

        if let adCreativeName = adCreativeName {
            dict["ad_creative_name"] = adCreativeName
        }

        if let assetName = assetName {
            dict["asset_name"] = assetName
        }
        
        if let installedAt = installedAt {
            dict["installed_at"] = dateFormatter.string(from: installedAt)
        }
        
        if let storeClickAt = storeClickAt {
            dict["store_click_at"] = dateFormatter.string(from: storeClickAt)
        }
        
        return dict
    }
}

public struct IntegrationData: Sendable {
    public let clevertapId: String?
    
    public init(clevertapId: String? = nil) {
        self.clevertapId = clevertapId
    }
    
    func toDictionary() -> SendableDictionary {
        var dict: SendableDictionary = [:]
        
        if let clevertapId = clevertapId {
            dict["clevertap_id"] = clevertapId
        }
        
        return dict
    }
}

public enum PaymentType: String, Sendable {
    case firstPayment = "FIRST_PAYMENT"
    case secondPayment = "SECOND_PAYMENT"
    case walletTopup = "WALLET_TOPUP"
    case fundsWithdrawal = "FUNDS_WITHDRAWAL"
    case subscriptionCreated = "SUBSCRIPTION_CREATED"
    case subscriptionRenewed = "SUBSCRIPTION_RENEWED"
    case oneTime = "ONE_TIME"
    case recurring = "RECURRING"
    case `default` = "DEFAULT"
}

public enum PaymentStatus: String, Sendable {
    case initiated = "PAYMENT_INITIATED"
    case completed = "PAYMENT_COMPLETED"
    case failed = "PAYMENT_FAILED"
    case cancelled = "PAYMENT_CANCELLED"
}

// MARK: - API Response Models

/// Response model for capture-payment endpoint
public struct CapturePaymentResponse: Codable, Sendable {
    public let success: Bool
    public let message: String
    public let data: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
    }
}

/// Response model for capture-event endpoint
public struct CaptureEventResponse: Codable, Sendable {
    public let success: Bool
    public let message: String
    public let data: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
    }
}

/// Response model for attribution data
public struct LRAttributionDataResponse: Codable, Sendable {
    
    public let attributionSource: String
    public let campaignData: CampaignData?
    public let deeplink: String?
    
    enum CodingKeys: String, CodingKey {
        case attributionSource = "attribution_source"
        case campaignData = "campaign_data"
        case deeplink
    }
    
    // Public initializer for creating empty/default responses
    public init(attributionSource: String, campaignData: CampaignData?, deeplink: String?) {
        self.attributionSource = attributionSource
        self.campaignData = campaignData
        self.deeplink = deeplink
    }
    
    // Custom decoder to handle Bool/Int conversion for rootDomain
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        attributionSource = try container.decodeIfPresent(String.self, forKey: .attributionSource) ?? "UNKNOWN"
        campaignData = try container.decodeIfPresent(CampaignData.self, forKey: .campaignData)
        deeplink = try container.decodeIfPresent(String.self, forKey: .deeplink)
    }
    
    // Legacy dictionary initializer for backward compatibility
    init(dictionary: SendableDictionary) throws {
        self.attributionSource = dictionary["attribution_source"] as? String ?? "UNKNOWN"
        
        // Handle campaign_data - can be null
        if let campaignDataDict = dictionary["campaign_data"] as? SendableDictionary {
            self.campaignData = try CampaignData(dictionary: campaignDataDict)
        } else {
            self.campaignData = nil
        }
        
        // Handle deeplink - can be null
        if let deeplink = dictionary["deeplink"] as? String, deeplink != "<null>" {
            self.deeplink = deeplink
        } else {
            self.deeplink = nil
        }
    }

    public func toDictionary() -> SendableDictionary {
        var dict: SendableDictionary = [
            "attribution_source": attributionSource
        ]
        
        if let campaignData = campaignData {
            dict["campaign_data"] = campaignData.toDictionary()
        }
        
        if let deeplink = deeplink {
            dict["deeplink"] = deeplink
        }
        
        return dict
    }
}

/// Response model for handle-deeplink endpoint
public struct LRDeeplinkResponse: Sendable {
    public let deeplink: String?
    public let isLinkrunner: Bool
    public let processing: Bool?

    public init(deeplink: String?, isLinkrunner: Bool, processing: Bool? = nil) {
        self.deeplink = deeplink
        self.isLinkrunner = isLinkrunner
        self.processing = processing
    }

    init(dictionary: SendableDictionary) {
        self.deeplink = dictionary["deeplink"] as? String
        self.isLinkrunner = dictionary["is_linkrunner"] as? Bool ?? false
        self.processing = dictionary["processing"] as? Bool
    }

    public func toDictionary() -> SendableDictionary {
        var dict: SendableDictionary = [
            "is_linkrunner": isLinkrunner
        ]
        if let deeplink = deeplink {
            dict["deeplink"] = deeplink
        }
        if let processing = processing {
            dict["processing"] = processing
        }
        return dict
    }
}
