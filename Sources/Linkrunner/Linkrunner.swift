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

#if canImport(Network)
import Network
#endif

@available(iOS 15.0, *)
public class LinkrunnerSDK: @unchecked Sendable {
    // Configuration option for PII hashing
    private var hashPII: Bool = false
    
    // Define a Sendable device data structure
    private struct DeviceData: Sendable {
        var device: String
        var deviceName: String
        var systemVersion: String
        var brand: String
        var manufacturer: String
        var bundleId: String?
        var appVersion: String?
        var buildNumber: String?
        var connectivity: String
        var deviceDisplay: DisplayData
        var idfa: String?
        var idfv: String?
        var locale: String?
        var language: String?
        var country: String?
        var timezone: String?
        var timezoneOffset: Int?
        var userAgent: String?
        var installInstanceId: String
        
        struct DisplayData: Sendable {
            var width: Double
            var height: Double
            var scale: Double
        }
        
        // Convert to dictionary for network requests
        func toDictionary() -> SendableDictionary {
            var dict: SendableDictionary = [
                "device": device,
                "device_name": deviceName,
                "system_version": systemVersion,
                "brand": brand,
                "manufacturer": manufacturer,
                "connectivity": connectivity,
                "device_display": [
                    "width": deviceDisplay.width,
                    "height": deviceDisplay.height,
                    "scale": deviceDisplay.scale
                ] as [String: Any],
                "install_instance_id": installInstanceId
            ]
            
            if let bundleId = bundleId { dict["bundle_id"] = bundleId }
            if let appVersion = appVersion { dict["version"] = appVersion }
            if let buildNumber = buildNumber { dict["build_number"] = buildNumber }
            if let idfa = idfa { dict["idfa"] = idfa }
            if let idfv = idfv { dict["idfv"] = idfv }
            if let locale = locale { dict["locale"] = locale }
            if let language = language { dict["language"] = language }
            if let country = country { dict["country"] = country }
            if let timezone = timezone { dict["timezone"] = timezone }
            if let timezoneOffset = timezoneOffset { dict["timezone_offset"] = timezoneOffset }
            if let userAgent = userAgent { dict["user_agent"] = userAgent }
            
            return dict
        }
    }
    // Network monitoring properties
#if canImport(Network)
    private var networkMonitor: NWPathMonitor?
    private var currentConnectionType: String?
#endif
    public static let shared = LinkrunnerSDK()
    
    private var token: String?
    private let baseUrl = "https://api.linkrunner.io"
    

    
#if canImport(Network)
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitoring")
        
        // Initialize the connection type before starting the monitor
        self.currentConnectionType = "unknown"
        
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            // Only check interface type when status is satisfied to avoid warnings
            if path.status == .satisfied {
                // Use a local variable to determine the connection type
                let connectionType: String
                
                // Simply check the interface type without accessing endpoints
                if path.usesInterfaceType(.wifi) {
                    connectionType = "wifi"
                } else if path.usesInterfaceType(.cellular) {
                    connectionType = "cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    connectionType = "ethernet"
                } else {
                    connectionType = "other"
                }
                
                // Update the connection type on the main object
                self?.currentConnectionType = connectionType
            } else {
                self?.currentConnectionType = "disconnected"
            }
        }
        
        networkMonitor?.start(queue: queue)
    }
#endif
    
    private init() {
#if canImport(Network)
        setupNetworkMonitoring()
#endif
    }
    
    // MARK: - Public Methods
    
    /// Initialize the Linkrunner SDK with your project token
    /// - Parameter token: Your Linkrunner project token
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func initialize(token: String) async throws {
        self.token = token
        return try await initApiCall(token: token, source: "GENERAL")
    }
    
    /// Enables or disables hashing of personally identifiable information (PII)
    /// - Parameter enabled: Whether PII hashing should be enabled
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func enablePIIHashing(_ enabled: Bool = true) {
        self.hashPII = enabled
    }
    
    /// Returns whether PII hashing is currently enabled
    /// - Returns: Boolean indicating if PII hashing is enabled
    public func isPIIHashingEnabled() -> Bool {
        return self.hashPII
    }
    
    /// Hashes a string using SHA-256 algorithm
    /// - Parameter input: The string to hash
    /// - Returns: Hashed string in hexadecimal format
    public func hashWithSHA256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }
    
    /// Register a user signup with Linkrunner
    /// - Parameter userData: User data to register
    /// - Parameter additionalData: Any additional data to include
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func signup(userData: UserData, additionalData: SendableDictionary? = nil) async throws {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        var requestData: SendableDictionary = [
            "token": token,
            "user_data": userData.toDictionary(hashPII: self.hashPII),
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        var dataDict: SendableDictionary = additionalData ?? [:]
        dataDict["device_data"] = (await deviceData()).toDictionary()
        requestData["data"] = dataDict
        
        do {
            _ = try await makeRequest(
                endpoint: "/api/client/trigger",
                body: requestData
            )
            
            // If we get here, the request was successful (makeRequest throws on error)
            #if DEBUG
            print("Linkrunner: Signup successful")
            #endif
            
        } catch {
            #if DEBUG
            print("Linkrunner: Signup failed with error: \(error)")
            #endif
            throw error
        }
    }
    
    /// Set user data in Linkrunner
    /// - Parameter userData: User data to set
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func setUserData(_ userData: UserData) async throws {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        let requestData: SendableDictionary = [
            "token": token,
            "user_data": userData.toDictionary(hashPII: self.hashPII),
            "device_data": (await deviceData()).toDictionary(),
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
                                body: ["token": token] as SendableDictionary
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
    public func requestTrackingAuthorization(completionHandler: (@Sendable (ATTrackingManager.AuthorizationStatus) -> Void)? = nil) {
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
                
                // Use Task to safely call the handler across isolation boundaries
                if let completionHandler = completionHandler {
                    Task { @MainActor in
                        completionHandler(status)
                    }
                }
            }
#else
            // Fallback when AppTrackingTransparency is not available
            print("Linkrunner: AppTrackingTransparency not available")
            if let completionHandler = completionHandler {
                Task { @MainActor in
                    completionHandler(.notDetermined)
                }
            }
#endif
        }
    }
    
    /// Track a custom event
    /// - Parameters:
    ///   - eventName: Name of the event
    ///   - eventData: Optional event data
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func trackEvent(eventName: String, eventData: SendableDictionary? = nil) async throws {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        if eventName.isEmpty {
            throw LinkrunnerError.invalidParameters("Event name is required")
        }
        
        let requestData: SendableDictionary = [
            "token": token,
            "event_name": eventName,
            "event_data": eventData as Any,
            "device_data": (await deviceData()).toDictionary(),
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
        
        var requestData: SendableDictionary = [
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
        
        var dataDict: SendableDictionary = [:]
        dataDict["device_data"] = (await deviceData()).toDictionary()
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
        ] as [String: Any])
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
        
        var requestData: SendableDictionary = [
            "token": token,
            "user_id": userId,
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        if let paymentId = paymentId {
            requestData["payment_id"] = paymentId
        }
        
        var dataDict: SendableDictionary = [:]
        dataDict["device_data"] = (await deviceData()).toDictionary()
        requestData["data"] = dataDict
        
        _ = try await makeRequest(
            endpoint: "/api/client/remove-captured-payment",
            body: requestData
        )
        
        #if DEBUG
        print("Linkrunner: Payment entry removed successfully!", [
            "paymentId": paymentId ?? "N/A",
            "userId": userId
        ] as [String: Any])
        #endif
    }
    
    /// Fetches attribution data for the current installation
    /// - Returns: The attribution data response
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func getAttributionData() async throws -> LRAttributionDataResponse {
        guard let token = self.token else {
            throw LinkrunnerError.notInitialized
        }
        
        let requestData: SendableDictionary = [
            "token": token,
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId(),
            "device_data": (await deviceData()).toDictionary()
        ]
        
        let response = try await makeRequest(
            endpoint: "/api/client/attribution-data",
            body: requestData
        )
        
        #if DEBUG
        print("Linkrunner: Fetching attribution data")
        #endif
        
        if let data = response["data"] as? SendableDictionary {
            return try LRAttributionDataResponse(dictionary: data)
        } else {
            throw LinkrunnerError.invalidResponse
        }
    }
    
    // MARK: - Private Methods
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func initApiCall(token: String, source: String, link: String? = nil) async throws {
        let deviceDataDict = (await deviceData()).toDictionary()
        let installInstanceId = await getLinkRunnerInstallInstanceId()
        
        var requestData: SendableDictionary = [
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
        
        do {
            _ = try await makeRequest(
                endpoint: "/api/client/init",
                body: requestData
            )
            
            // If we get here, the request was successful (makeRequest throws on error)
            #if DEBUG
            print("Linkrunner: Initialization successful")
            #endif
            
        } catch {
            #if DEBUG
            print("Linkrunner: Init failed with error: \(error)")
            #endif
            throw error
        }
    }
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func makeRequest(endpoint: String, body: SendableDictionary) async throws -> SendableDictionary {
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
        
        // Convert to SendableDictionary to ensure sendable compliance
        let sendableJson = json as SendableDictionary
        return sendableJson
    }
    
    private func getPackageVersion() -> String {
        return "1.0.6" // Swift package version
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Device Data

@available(iOS 15.0, *)
extension LinkrunnerSDK {
    private func deviceData() async -> DeviceData {
        // Create a Sendable wrapper using Task isolation to convert to a Sendable result
        return await Task { () -> DeviceData in
#if canImport(UIKit)
            // Device info
            let currentDevice = await UIDevice.current
            let deviceModel = await currentDevice.model
            let deviceName = await currentDevice.name
            let systemVersion = await currentDevice.systemVersion
            
            // App info
            let bundle = Bundle.main
            let bundleId = bundle.bundleIdentifier
            let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String
            
            // Network info
            let connectivity = getNetworkType()
            
            // Screen info
            let screen = await UIScreen.main
            let screenBounds = await screen.bounds
            let screenScale = await screen.scale
            let displayData = DeviceData.DisplayData(
                width: screenBounds.width,
                height: screenBounds.height,
                scale: screenScale
            )
            
            // Variable for IDFA
            var idfa: String? = nil
            
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
                idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
#endif
            }
#endif
            
            // Device ID (for IDFV)
            let identifierForVendor = await currentDevice.identifierForVendor
            let idfv = identifierForVendor?.uuidString
            
            // Locale info
            let locale = Locale.current
            let localeIdentifier = locale.identifier
            let languageCode = locale.languageCode
            let regionCode = locale.regionCode
            
            // Timezone
            let timezone = TimeZone.current
            let timezoneIdentifier = timezone.identifier
            let timezoneOffset = timezone.secondsFromGMT() / 60
            
            // User agent
            let userAgent = await getUserAgent()
            
            // Install instance ID
            let installInstanceId = await getLinkRunnerInstallInstanceId()
            
            return DeviceData(
                device: deviceModel,
                deviceName: deviceName,
                systemVersion: systemVersion,
                brand: "Apple",
                manufacturer: "Apple",
                bundleId: bundleId,
                appVersion: appVersion,
                buildNumber: buildNumber,
                connectivity: connectivity,
                deviceDisplay: displayData,
                idfa: idfa,
                idfv: idfv,
                locale: localeIdentifier,
                language: languageCode,
                country: regionCode,
                timezone: timezoneIdentifier,
                timezoneOffset: timezoneOffset,
                userAgent: userAgent,
                installInstanceId: installInstanceId
            )
#else
            // Fallback for non-UIKit platforms
            return DeviceData(
                device: "Unknown",
                deviceName: "Unknown",
                systemVersion: "Unknown",
                brand: "Apple",
                manufacturer: "Apple",
                bundleId: nil,
                appVersion: nil,
                buildNumber: nil,
                connectivity: "unknown",
                deviceDisplay: DeviceData.DisplayData(width: 0, height: 0, scale: 1),
                idfa: nil,
                idfv: nil,
                locale: nil,
                language: nil,
                country: nil,
                timezone: nil,
                timezoneOffset: nil,
                userAgent: nil,
                installInstanceId: await getLinkRunnerInstallInstanceId()
            )
#endif
        }.value
    }
    
    private func getNetworkType() -> String {
#if canImport(Network)
        // Using a static property to keep track of the network type
        // This helps avoid creating a new monitor for each call
        if networkMonitor == nil {
            setupNetworkMonitoring()
            // Return "unknown" immediately after setup to avoid race condition
            return "unknown"
        }
        
        // Thread-safe access to the current connection type
        let connectionType = currentConnectionType ?? "unknown"
        return connectionType
#else
        // Fallback for platforms where Network framework is not available
        return "unknown"
#endif
    }
    
    private func getUserAgent() async -> String {
#if canImport(UIKit)
        let device = await UIDevice.current
        let appInfo = Bundle.main.infoDictionary
        let appVersion = appInfo?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = appInfo?["CFBundleVersion"] as? String ?? "Unknown"
        let deviceModel = await device.model
        let systemVersion = await device.systemVersion
        
        return "Linkrunner-iOS/\(appVersion) (\(deviceModel); iOS \(systemVersion); Build/\(buildNumber))"
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