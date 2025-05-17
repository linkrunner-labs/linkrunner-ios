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

public struct LRIPLocationData: Codable, Sendable {
    public let ip: String
    public let city: String
    public let countryLong: String
    public let countryShort: String
    public let latitude: Double
    public let longitude: Double
    public let region: String
    public let timeZone: String
    public let zipCode: String
    
    enum CodingKeys: String, CodingKey {
        case ip
        case city
        case countryLong = "country_long"
        case countryShort = "country_short"
        case latitude
        case longitude
        case region
        case timeZone = "time_zone"
        case zipCode = "zip_code"
    }
    
    // Legacy dictionary initializer for backward compatibility
    init(dictionary: SendableDictionary) throws {
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

public struct UserData: Sendable {
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
    
    var dictionary: SendableDictionary {
        var dict: SendableDictionary = ["id": id]
        
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

public struct LRInitResponse: Codable, Sendable {
    public let attributionSource: String
    public let campaignData: CampaignData?
    public let deeplink: String?
    public let ipLocationData: LRIPLocationData
    public let rootDomain: Bool
    
    enum CodingKeys: String, CodingKey {
        case attributionSource = "attribution_source"
        case campaignData = "campaign_data"
        case deeplink
        case ipLocationData = "ip_location_data"
        case rootDomain = "root_domain"
    }
    
    // Custom decoder to handle Bool/Int conversion for rootDomain
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        attributionSource = try container.decodeIfPresent(String.self, forKey: .attributionSource) ?? "UNKNOWN"
        campaignData = try container.decodeIfPresent(CampaignData.self, forKey: .campaignData)
        deeplink = try container.decodeIfPresent(String.self, forKey: .deeplink)
        ipLocationData = try container.decode(LRIPLocationData.self, forKey: .ipLocationData)
        
        // Handle Boolean or Integer 0/1 representation
        if let boolValue = try? container.decode(Bool.self, forKey: .rootDomain) {
            rootDomain = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .rootDomain) {
            rootDomain = intValue != 0
        } else {
            rootDomain = false
        }
    }
    
    // Legacy dictionary initializer for backward compatibility
    init(dictionary: SendableDictionary) throws {
        guard let ipLocationDataDict = dictionary["ip_location_data"] as? SendableDictionary else {
            throw LinkrunnerError.invalidResponse
        }
        
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
        
        self.ipLocationData = try LRIPLocationData(dictionary: ipLocationDataDict)
        
        // Convert rootDomain to Bool
        if let rootDomain = dictionary["root_domain"] as? Int {
            self.rootDomain = rootDomain != 0
        } else if let rootDomain = dictionary["root_domain"] as? Bool {
            self.rootDomain = rootDomain
        } else {
            self.rootDomain = false
        }
    }
}

public struct LRTriggerResponse: Codable, Sendable {
    public let ipLocationData: LRIPLocationData
    public let deeplink: String?
    public let rootDomain: Bool
    public let trigger: Bool?
    public let campaignData: CampaignData?
    public let attributionSource: String
    
    enum CodingKeys: String, CodingKey {
        case ipLocationData = "ip_location_data"
        case deeplink
        case rootDomain = "root_domain"
        case trigger
        case campaignData = "campaign_data"
        case attributionSource = "attribution_source"
    }
    
    // Custom decoder to handle Bool/Int conversion for rootDomain
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        ipLocationData = try container.decode(LRIPLocationData.self, forKey: .ipLocationData)
        deeplink = try container.decodeIfPresent(String.self, forKey: .deeplink)
        attributionSource = try container.decodeIfPresent(String.self, forKey: .attributionSource) ?? "UNKNOWN"
        trigger = try container.decodeIfPresent(Bool.self, forKey: .trigger)
        campaignData = try container.decodeIfPresent(CampaignData.self, forKey: .campaignData)
        
        // Handle Boolean or Integer 0/1 representation
        if let boolValue = try? container.decode(Bool.self, forKey: .rootDomain) {
            rootDomain = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .rootDomain) {
            rootDomain = intValue != 0
        } else {
            rootDomain = false
        }
    }
    
    // Legacy dictionary initializer for backward compatibility
    init(dictionary: SendableDictionary) throws {
        guard let ipLocationDataDict = dictionary["ip_location_data"] as? SendableDictionary else {
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
        
        // Convert rootDomain to Bool
        if let rootDomain = dictionary["root_domain"] as? Int {
            self.rootDomain = rootDomain != 0
        } else if let rootDomain = dictionary["root_domain"] as? Bool {
            self.rootDomain = rootDomain
        } else {
            self.rootDomain = false
        }
        
        // Handle trigger flag
        self.trigger = dictionary["trigger"] as? Bool
        
        // Handle campaign_data - can be null
        if let campaignDataDict = dictionary["campaign_data"] as? SendableDictionary {
            self.campaignData = try CampaignData(dictionary: campaignDataDict)
        } else {
            self.campaignData = nil
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