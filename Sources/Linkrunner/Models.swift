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

// MARK: - Model Types

public struct LRIPLocationData: Codable {
    public let ip: String
    public let city: String
    public let countryLong: String
    public let countryShort: String
    public let latitude: Double
    public let longitude: Double
    public let region: String
    public let timeZone: String
    public let zipCode: String
    
    init(dictionary: [String: Any]) throws {
        guard let ip = dictionary["ip"] as? String,
              let city = dictionary["city"] as? String,
              let countryLong = dictionary["countryLong"] as? String,
              let countryShort = dictionary["countryShort"] as? String,
              let latitude = dictionary["latitude"] as? Double,
              let longitude = dictionary["longitude"] as? Double,
              let region = dictionary["region"] as? String,
              let timeZone = dictionary["timeZone"] as? String,
              let zipCode = dictionary["zipCode"] as? String else {
            throw LinkrunnerError.invalidResponse
        }
        
        self.ip = ip
        self.city = city
        self.countryLong = countryLong
        self.countryShort = countryShort
        self.latitude = latitude
        self.longitude = longitude
        self.region = region
        self.timeZone = timeZone
        self.zipCode = zipCode
    }
}

public struct UserData {
    public let id: String
    public let name: String?
    public let phone: String?
    public let email: String?
    
    public init(id: String, name: String? = nil, phone: String? = nil, email: String? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = ["id": id]
        
        if let name = name {
            dict["name"] = name
        }
        
        if let phone = phone {
            dict["phone"] = phone
        }
        
        if let email = email {
            dict["email"] = email
        }
        
        return dict
    }
}

public struct CampaignData: Codable {
    public let id: String
    public let name: String
    public let type: String // "ORGANIC" or "INORGANIC"
    public let adNetwork: String? // "META" or "GOOGLE" or null
    public let groupName: String?
    public let assetGroupName: String?
    public let assetName: String?
    public let installedAt: Date?
    public let storeClickAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, name, type
        case adNetwork = "ad_network"
        case groupName = "group_name"
        case assetGroupName = "asset_group_name"
        case assetName = "asset_name"
        case installedAt = "installed_at"
        case storeClickAt = "store_click_at"
    }
    
    init(dictionary: [String: Any]) throws {
        guard let id = dictionary["id"] as? String,
              let name = dictionary["name"] as? String,
              let type = dictionary["type"] as? String else {
            throw LinkrunnerError.invalidResponse
        }
        
        self.id = id
        self.name = name
        self.type = type
        self.adNetwork = dictionary["ad_network"] as? String
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

public struct LRInitResponse {
    public let attributionSource: String
    public let campaignData: CampaignData?
    public let deeplink: String?
    public let ipLocationData: LRIPLocationData
    public let rootDomain: Int
    
    init(dictionary: [String: Any]) throws {
        guard let ipLocationDataDict = dictionary["ip_location_data"] as? [String: Any] else {
            throw LinkrunnerError.invalidResponse
        }
        
        self.attributionSource = dictionary["attribution_source"] as? String ?? "UNKNOWN"
        
        // Handle campaign_data - can be null
        if let campaignDataDict = dictionary["campaign_data"] as? [String: Any] {
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
        
        self.ipLocationData = try LRIPLocationData(dictionary: ipLocationDataDict)
        
        // root_domain can be 0 (Int) instead of a Bool
        if let rootDomain = dictionary["root_domain"] as? Int {
            self.rootDomain = rootDomain
        } else if let rootDomain = dictionary["root_domain"] as? Bool {
            self.rootDomain = rootDomain ? 1 : 0
        } else {
            self.rootDomain = 0
        }
    }
}

public struct LRTriggerResponse {
    public let ipLocationData: LRIPLocationData
    public let deeplink: String?
    public let rootDomain: Int
    public let trigger: Bool?
    public let campaignData: CampaignData?
    public let attributionSource: String
    
    init(dictionary: [String: Any]) throws {
        guard let ipLocationDataDict = dictionary["ip_location_data"] as? [String: Any] else {
            throw LinkrunnerError.invalidResponse
        }
        
        self.ipLocationData = try LRIPLocationData(dictionary: ipLocationDataDict)
        
        // Handle deeplink - can be null
        if let deeplink = dictionary["deeplink"] as? String, deeplink != "<null>" {
            self.deeplink = deeplink
        } else {
            self.deeplink = nil
        }
        
        // Handle attribution_source
        self.attributionSource = dictionary["attribution_source"] as? String ?? "UNKNOWN"
        
        // Handle root_domain (can be Int or Bool)
        if let rootDomain = dictionary["root_domain"] as? Int {
            self.rootDomain = rootDomain
        } else if let rootDomain = dictionary["root_domain"] as? Bool {
            self.rootDomain = rootDomain ? 1 : 0
        } else {
            self.rootDomain = 0
        }
        
        // Handle trigger flag
        self.trigger = dictionary["trigger"] as? Bool
        
        // Handle campaign_data - can be null
        if let campaignDataDict = dictionary["campaign_data"] as? [String: Any] {
            self.campaignData = try CampaignData(dictionary: campaignDataDict)
        } else {
            self.campaignData = nil
        }
    }
}

public enum PaymentType: String {
    case firstPayment = "FIRST_PAYMENT"
    case walletTopup = "WALLET_TOPUP"
    case fundsWithdrawal = "FUNDS_WITHDRAWAL"
    case subscriptionCreated = "SUBSCRIPTION_CREATED"
    case subscriptionRenewed = "SUBSCRIPTION_RENEWED"
    case oneTime = "ONE_TIME"
    case recurring = "RECURRING"
    case `default` = "DEFAULT"
}

public enum PaymentStatus: String {
    case initiated = "PAYMENT_INITIATED"
    case completed = "PAYMENT_COMPLETED"
    case failed = "PAYMENT_FAILED"
    case cancelled = "PAYMENT_CANCELLED"
}
