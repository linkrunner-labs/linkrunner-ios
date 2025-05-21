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
    
    public init(id: String, name: String? = nil, phone: String? = nil, email: String? = nil, isFirstTimeUser: Bool? = nil, userCreatedAt: String? = nil, mixPanelDistinctId: String? = nil, amplitudeDeviceId: String? = nil, posthogDistinctId: String? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.isFirstTimeUser = isFirstTimeUser
        self.userCreatedAt = userCreatedAt
        self.mixPanelDistinctId = mixPanelDistinctId
        self.amplitudeDeviceId = amplitudeDeviceId
        self.posthogDistinctId = posthogDistinctId
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
}

public enum PaymentType: String, Sendable {
    case firstPayment = "FIRST_PAYMENT"
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
}
