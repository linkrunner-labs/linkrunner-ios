import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AdSupport)
import AdSupport
#endif

#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

@available(iOS 15.0, *)
public class LinkrunnerSDK: @unchecked Sendable {
    public static let shared = LinkrunnerSDK()
    
    private var token: String?
    private let baseUrl = "https://api.linkrunner.io"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Initialize the Linkrunner SDK with your project token
    /// - Parameter token: Your Linkrunner project token
    /// - Returns: The initialization response
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func initialize(token: String) async throws -> LRInitResponse {
        self.token = token
        
        return try await initApiCall(token: token, source: "GENERAL")
    }
    
    /// Register a user signup with Linkrunner
    /// - Parameter userData: User data to register
    /// - Parameter additionalData: Any additional data to include
    /// - Returns: The trigger response
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func signup(userData: UserData, additionalData: [String: Any]? = nil) async throws -> LRTriggerResponse {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        var requestData: [String: Any] = [
            "token": token,
            "user_data": userData.dictionary,
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        var dataDict: [String: Any] = additionalData ?? [:]
        dataDict["device_data"] = await deviceData()
        requestData["data"] = dataDict
        
        let response = try await makeRequest(
            endpoint: "/api/client/trigger",
            body: requestData
        )
        
        #if DEBUG
        print("Linkrunner: Signup called ")
        #endif
        
        if let data = response["data"] as? [String: Any] {
            return try LRTriggerResponse(dictionary: data)
        } else {
            throw LinkrunnerError.invalidResponse
        }
    }
    
    /// Set user data in Linkrunner
    /// - Parameter userData: User data to set
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func setUserData(_ userData: UserData) async throws {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        let requestData: [String: Any] = [
            "token": token,
            "user_data": userData.dictionary,
            "device_data": await deviceData(),
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        _ = try await makeRequest(
            endpoint: "/api/client/set-user-data",
            body: requestData
        )
    }
    
    /// Trigger the deeplink that led to app installation
    public func triggerDeeplink() async {
        guard let deeplinkUrl = try? await getDeeplinkURL(),
              let url = URL(string: deeplinkUrl) else {
            print("Linkrunner: Deeplink URL not found")
            return
        }
        
        DispatchQueue.main.async {
#if canImport(UIKit)
            UIApplication.shared.open(url) { success in
                if success {
                    Task {
                        guard let token = self.token else { return }
                        
                        do {
                            let _ = try await self.makeRequest(
                                endpoint: "/api/client/deeplink-triggered",
                                body: ["token": token]
                            )
                            
                            #if DEBUG
                            print("Linkrunner: Deeplink triggered successfully", deeplinkUrl)
                            #endif
                        } catch {
                            #if DEBUG
                            print("Linkrunner: Deeplink triggering failed", deeplinkUrl)
                            #endif
                        }
                    }
                }
            }
#else
            print("Linkrunner: UIApplication not available to open URLs")
#endif
        }
    }
    
    /// Request App Tracking Transparency permission
    /// - Parameter completionHandler: Optional callback with the authorization status
    /// - Returns: The tracking authorization status
    public func requestTrackingAuthorization(completionHandler: ((ATTrackingManager.AuthorizationStatus) -> Void)? = nil) {
        DispatchQueue.main.async {
#if canImport(AppTrackingTransparency)
            ATTrackingManager.requestTrackingAuthorization { status in
                #if DEBUG
                var statusString = ""
                switch status {
                case .notDetermined: statusString = "Not Determined"
                case .restricted: statusString = "Restricted"
                case .denied: statusString = "Denied"
                case .authorized: statusString = "Authorized"
                @unknown default: statusString = "Unknown"
                }
                
                print("Linkrunner: Tracking authorization status: \(statusString)")
                #endif
                
                completionHandler?(status)
            }
#else
            // Fallback when AppTrackingTransparency is not available
            print("Linkrunner: AppTrackingTransparency not available")
            completionHandler?(.notDetermined)
#endif
        }
    }
    
    /// Track a custom event
    /// - Parameters:
    ///   - eventName: Name of the event
    ///   - eventData: Optional event data
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func trackEvent(eventName: String, eventData: [String: Any]? = nil) async throws {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        if eventName.isEmpty {
            throw LinkrunnerError.invalidParameters("Event name is required")
        }
        
        let requestData: [String: Any] = [
            "token": token,
            "event_name": eventName,
            "event_data": eventData as Any,
            "device_data": await deviceData(),
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        _ = try await makeRequest(
            endpoint: "/api/client/capture-event",
            body: requestData
        )
        
        #if DEBUG
        print("Linkrunner: Tracking event", eventName, eventData ?? [:])
        #endif
    }
    
    /// Capture a payment
    /// - Parameters:
    ///   - amount: Payment amount
    ///   - userId: User identifier
    ///   - paymentId: Optional payment identifier
    ///   - type: Optional payment type
    ///   - status: Optional payment status
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func capturePayment(
        amount: Double,
        userId: String,
        paymentId: String? = nil,
        type: PaymentType = .default,
        status: PaymentStatus = .completed
    ) async throws {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        var requestData: [String: Any] = [
            "token": token,
            "user_id": userId,
            "platform": "IOS",
            "amount": amount,
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        if let paymentId = paymentId {
            requestData["payment_id"] = paymentId
        }
        
        requestData["type"] = type.rawValue
        requestData["status"] = status.rawValue
        
        var dataDict: [String: Any] = [:]
        dataDict["device_data"] = await deviceData()
        requestData["data"] = dataDict
        
        _ = try await makeRequest(
            endpoint: "/api/client/capture-payment",
            body: requestData
        )
        
        #if DEBUG
        print("Linkrunner: Payment captured successfully ", [
            "amount": amount,
            "paymentId": paymentId ?? "N/A",
            "userId": userId,
            "type": type.rawValue,
            "status": status.rawValue
        ])
        #endif
    }
    
    /// Remove a captured payment
    /// - Parameters:
    ///   - userId: User identifier
    ///   - paymentId: Optional payment identifier
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func removePayment(userId: String, paymentId: String? = nil) async throws {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        if paymentId == nil && userId.isEmpty {
            throw LinkrunnerError.invalidParameters("Either paymentId or userId must be provided")
        }
        
        var requestData: [String: Any] = [
            "token": token,
            "user_id": userId,
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        if let paymentId = paymentId {
            requestData["payment_id"] = paymentId
        }
        
        var dataDict: [String: Any] = [:]
        dataDict["device_data"] = await deviceData()
        requestData["data"] = dataDict
        
        _ = try await makeRequest(
            endpoint: "/api/client/remove-captured-payment",
            body: requestData
        )
        
        #if DEBUG
        print("Linkrunner: Payment entry removed successfully!", [
            "paymentId": paymentId ?? "N/A",
            "userId": userId
        ])
        #endif
    }
    
    // MARK: - Private Methods
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func initApiCall(token: String, source: String, link: String? = nil) async throws -> LRInitResponse {
        let deviceDataDict = await deviceData()
        let installInstanceId = await getLinkRunnerInstallInstanceId()
        
        var requestData: [String: Any] = [
            "token": token,
            "package_version": getPackageVersion(),
            "app_version": getAppVersion(),
            "device_data": deviceDataDict,
            "platform": "IOS",
            "source": source,
            "install_instance_id": installInstanceId
        ]
        
        if let link = link {
            requestData["link"] = link
        }
        
        let response = try await makeRequest(
            endpoint: "/api/client/init",
            body: requestData
        )
        
        #if DEBUG
        print("Linkrunner initialized successfully ")
        print("init response > ", response)
        #endif
        
        if let data = response["data"] as? [String: Any],
           let deeplink = data["deeplink"] as? String {
            await setDeeplinkURL(deeplink)
        }
        
        if let data = response["data"] as? [String: Any] {
            return try LRInitResponse(dictionary: data)
        } else {
            throw LinkrunnerError.invalidResponse
        }
    }
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func makeRequest(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: baseUrl + endpoint) else {
            throw LinkrunnerError.invalidUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw LinkrunnerError.jsonEncodingFailed
        }
        
        // Since this method is already marked with @available for iOS 15+, we can directly use URLSession.shared.data(for:)        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkrunnerError.invalidResponse
        }
        
        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            throw LinkrunnerError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw LinkrunnerError.jsonDecodingFailed
        }
        
        return json
    }
    
    private func getPackageVersion() -> String {
        return "1.0.0" // Swift package version
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Device Data

@available(iOS 15.0, *)
extension LinkrunnerSDK {
    private func deviceData() async -> [String: Any] {
#if canImport(UIKit)
        var data: [String: Any] = [:]
        
        // Device info
        data["device"] = await UIDevice.current.model
        data["device_name"] = await UIDevice.current.name
        data["system_version"] = await UIDevice.current.systemVersion
        data["brand"] = "Apple"
        data["manufacturer"] = "Apple"
        
        // App info
        let bundle = Bundle.main
        data["bundle_id"] = bundle.bundleIdentifier
        data["version"] = bundle.infoDictionary?["CFBundleShortVersionString"]
        data["build_number"] = bundle.infoDictionary?["CFBundleVersion"]
        
        // Network info
        data["connectivity"] = getNetworkType()
        
        // Screen info
        let screen = await UIScreen.main
        data["device_display"] = await [
            "width": screen.bounds.width,
            "height": screen.bounds.height,
            "scale": screen.scale
        ]
        
        // Advertising ID
#if canImport(AppTrackingTransparency)
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            // Create a continuation to make the async SDK call work in our async function
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    ATTrackingManager.requestTrackingAuthorization { _ in
                        continuation.resume()
                    }
                }
            }
        }
        
        // Check the status after potential request
        if ATTrackingManager.trackingAuthorizationStatus == .authorized {
#if canImport(AdSupport)
            data["idfa"] = ASIdentifierManager.shared().advertisingIdentifier.uuidString
#endif
        }
#endif
        
        // Device ID (for IDFV)
        data["idfv"] = await UIDevice.current.identifierForVendor?.uuidString
        
        // Locale info
        let locale = Locale.current
        data["locale"] = locale.identifier
        data["language"] = locale.languageCode
        data["country"] = locale.regionCode
        
        // Timezone
        let timezone = TimeZone.current
        data["timezone"] = timezone.identifier
        data["timezone_offset"] = timezone.secondsFromGMT() / 60
        
        // User agent
        data["user_agent"] = await getUserAgent()
        
#else
        // Fallback for non-UIKit platforms
        var data: [String: Any] = [:]
        data["platform"] = "iOS"
#endif
        return data
    }
    
    private func getNetworkType() -> String {
        // This is a simplified version - in a real implementation,
        // you would use the Network framework or Reachability to check
        return "unknown"
    }
    
    private func getUserAgent() async -> String {
#if canImport(UIKit)
        let device = await UIDevice.current
        let appInfo = Bundle.main.infoDictionary
        let appVersion = appInfo?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = appInfo?["CFBundleVersion"] as? String ?? "Unknown"
        
        return "Linkrunner-iOS/\(appVersion) (\(await device.model); iOS \(await device.systemVersion); Build/\(buildNumber))"
#else
        return "Linkrunner-iOS/Unknown"
#endif
    }
}

// MARK: - Storage Methods

extension LinkrunnerSDK {
    private static let STORAGE_KEY = "linkrunner_install_instance_id"
    private static let DEEPLINK_URL_STORAGE_KEY = "linkrunner_deeplink_url"
    private static let ID_LENGTH = 20
    
    private func getLinkRunnerInstallInstanceId() async -> String {
        if let installInstanceId = UserDefaults.standard.string(forKey: LinkrunnerSDK.STORAGE_KEY) {
            return installInstanceId
        }
        
        let installInstanceId = generateRandomString(length: LinkrunnerSDK.ID_LENGTH)
        UserDefaults.standard.set(installInstanceId, forKey: LinkrunnerSDK.STORAGE_KEY)
        return installInstanceId
    }
    
    private func generateRandomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in
            chars.randomElement()!
        })
    }
    
    private func setDeeplinkURL(_ deeplinkURL: String) async {
        UserDefaults.standard.set(deeplinkURL, forKey: LinkrunnerSDK.DEEPLINK_URL_STORAGE_KEY)
    }
    
    private func getDeeplinkURL() async throws -> String? {
        return UserDefaults.standard.string(forKey: LinkrunnerSDK.DEEPLINK_URL_STORAGE_KEY)
    }
}
