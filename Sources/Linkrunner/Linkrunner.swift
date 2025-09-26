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
    // Configuration options
    private var hashPII: Bool = false
    private var disableIdfa: Bool = false
    private var debug: Bool = false
    
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
    private var secretKey: String?
    private var keyId: String?
    
    // Time tracking for SKAN
    private var appInstallTime: Date?
    
    // Request signing configuration
    private let requestInterceptor = RequestSigningInterceptor()
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
    
    /// Configure request signing using raw key data
    /// - Parameters:
    ///   - secretKey: Secret key for HMAC signing
    ///   - keyId: Key identifier for HMAC signing
    public func configureRequestSigning(secretKey: String, keyId: String) {
        requestInterceptor.configure(secretKey: secretKey, keyId: keyId)
    }
    
    /// Reset request signing configuration
    public func resetRequestSigning() {
        requestInterceptor.reset()
    }
    
    /// Initialize the Linkrunner SDK with your project token
    /// - Parameter token: Your Linkrunner project token
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func initialize(token: String, secretKey: String? = nil, keyId: String? = nil, disableIdfa: Bool? = false, debug: Bool? = false) async {
        self.token = token
        self.disableIdfa = disableIdfa ?? false
        self.debug = debug ?? false
        
        // Set app install time on first initialization
        if appInstallTime == nil {
            appInstallTime = getAppInstallTime()
            
            // Initialize SKAN with default values (0/low) on first init
            await SKAdNetworkService.shared.registerInitialConversionValue()
        }
        
        // Only set secretKey and keyId when they are provided
        if let secretKey = secretKey, let keyId = keyId, !secretKey.isEmpty, !keyId.isEmpty {
            self.secretKey = secretKey
            self.keyId = keyId
            
            // Configure request signing only when both secretKey and keyId are provided
            configureRequestSigning(secretKey: secretKey, keyId: keyId)
        }
        await initApiCall(token: token, source: "GENERAL", debug: debug)
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
    public func signup(userData: UserData, additionalData: SendableDictionary? = nil) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: Signup failed - SDK not initialized")
            #endif
            return
        }
        
        var requestData: SendableDictionary = [
            "token": token,
            "user_data": userData.toDictionary(hashPII: self.hashPII),
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId(),
            "time_since_app_install": getTimeSinceAppInstall()
        ]
        
        var dataDict: SendableDictionary = additionalData ?? [:]
        dataDict["device_data"] = (await deviceData()).toDictionary()
        requestData["data"] = dataDict
        
        do {
            let response = try await makeRequest(
                endpoint: "/api/client/trigger",
                body: requestData
            )

            // Process SKAN conversion values from response in background
            await processSKANResponse(response, source: "signup")
            
        } catch {
            #if DEBUG
            print("Linkrunner: Signup failed with error: \(error)")
            #endif
        }
    }
    
    /// Set user data in Linkrunner
    /// - Parameter userData: User data to set
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func setUserData(_ userData: UserData) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: setUserData failed - SDK not initialized")
            #endif
            return
        }
        
        let requestData: SendableDictionary = [
            "token": token,
            "user_data": userData.toDictionary(hashPII: self.hashPII),
            "device_data": (await deviceData()).toDictionary(),
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        do {
            _ = try await makeRequest(
                endpoint: "/api/client/set-user-data",
                body: requestData
            )
        } catch {
            #if DEBUG
            print("Linkrunner: setUserData failed with error: \(error)")
            #endif
        }
    }
    
    /// Set additional integration data
    /// - Parameter integrationData: The integration data to set
    /// - Returns: The response from the server, if any
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func setAdditionalData(_ integrationData: IntegrationData) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: setAdditionalData failed - SDK not initialized")
            #endif
            return
        }
        
        let integrationDict = integrationData.toDictionary()
        if integrationDict.isEmpty {
            #if DEBUG
            print("Linkrunner: setAdditionalData failed - Integration data is required")
            #endif
            return
        }
        
        let installInstanceId = await getLinkRunnerInstallInstanceId()
        let requestData: SendableDictionary = [
            "token": token,
            "install_instance_id": installInstanceId,
            "integration_info": integrationDict,
            "platform": "IOS"
        ]
        
        do {
            let response = try await makeRequest(
                endpoint: "/api/client/integrations",
                body: requestData
            )
            
            guard let status = response["status"] as? Int, (status == 200 || status == 201) else {
                let msg = response["msg"] as? String ?? "Unknown error"
                #if DEBUG
                print("Linkrunner: setAdditionalData failed with API error: \(msg)")
                #endif
                return
            }
        } catch {
            #if DEBUG
            print("Linkrunner: setAdditionalData failed with error: \(error)")
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
    public func trackEvent(eventName: String, eventData: SendableDictionary? = nil) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: trackEvent failed - SDK not initialized")
            #endif
            return
        }
        
        if eventName.isEmpty {
            #if DEBUG
            print("Linkrunner: trackEvent failed - Event name is required")
            #endif
            return
        }
        
        let requestData: SendableDictionary = [
            "token": token,
            "event_name": eventName,
            "event_data": eventData as Any,
            "device_data": (await deviceData()).toDictionary(),
            "install_instance_id": await getLinkRunnerInstallInstanceId(),
            "time_since_app_install": getTimeSinceAppInstall(),
            "platform": "IOS"
        ]
        
        do {
            let response = try await makeRequest(
                endpoint: "/api/client/capture-event",
                body: requestData
            )
            
            // Process SKAN conversion values from response in background
            await processSKANResponse(response, source: "event")
            
            #if DEBUG
            print("Linkrunner: Tracking event", eventName, eventData ?? [:])
            #endif
        } catch {
            #if DEBUG
            print("Linkrunner: trackEvent failed with error: \(error)")
            #endif
        }
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
    ) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: capturePayment failed - SDK not initialized")
            #endif
            return
        }
        
        var requestData: SendableDictionary = [
            "token": token,
            "user_id": userId,
            "platform": "IOS",
            "amount": amount,
            "install_instance_id": await getLinkRunnerInstallInstanceId(),
            "time_since_app_install": getTimeSinceAppInstall(),
        ]
        
        if let paymentId = paymentId {
            requestData["payment_id"] = paymentId
        }
        
        requestData["type"] = type.rawValue
        requestData["status"] = status.rawValue
        
        var dataDict: SendableDictionary = [:]
        dataDict["device_data"] = (await deviceData()).toDictionary()
        requestData["data"] = dataDict
        
        do {
            let response = try await makeRequest(
                endpoint: "/api/client/capture-payment",
                body: requestData
            )
            
            // Process SKAN conversion values from response in background
            await processSKANResponse(response, source: "payment")
            
            #if DEBUG
            print("Linkrunner: Payment captured successfully ", [
                "amount": amount,
                "paymentId": paymentId ?? "N/A",
                "userId": userId,
                "type": type.rawValue,
                "status": status.rawValue
            ] as [String: Any])
            #endif
        } catch {
            #if DEBUG
            print("Linkrunner: capturePayment failed with error: \(error)")
            #endif
        }
    }
    
    /// Remove a captured payment
    /// - Parameters:
    ///   - userId: User identifier
    ///   - paymentId: Optional payment identifier
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func removePayment(userId: String, paymentId: String? = nil) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: removePayment failed - SDK not initialized")
            #endif
            return
        }
        
        if paymentId == nil && userId.isEmpty {
            #if DEBUG
            print("Linkrunner: removePayment failed - Either paymentId or userId must be provided")
            #endif
            return
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
        
        do {
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
        } catch {
            #if DEBUG
            print("Linkrunner: removePayment failed with error: \(error)")
            #endif
        }
    }
    
    /// Fetches attribution data for the current installation
    /// - Returns: The attribution data response
    // to ensure backward compatibility we return empty LRAttributionDataResponse on error
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func getAttributionData() async -> LRAttributionDataResponse {
        guard let token = self.token else {
            #if DEBUG
            print("GetAttributionData: SDK not initialized")
            #endif
            return LRAttributionDataResponse(
                attributionSource: "Error getting attribution data",
                campaignData: nil,  
                deeplink: nil
            )
        }
        
        let requestData: SendableDictionary = [
            "token": token,
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId(),
            "device_data": (await deviceData()).toDictionary(),
            "debug": self.debug
        ]

        do {
            let response = try await makeRequestWithoutRetry(
                endpoint: "/api/client/attribution-data",
                body: requestData
            )
            
            #if DEBUG
            print("LinkrunnerKit: Fetching attribution data")
            #endif
            
            if let data = response["data"] as? SendableDictionary {
                return try LRAttributionDataResponse(dictionary: data)
            } else {
                #if DEBUG
                print("GetAttributionData: Invalid response")
                #endif
                return LRAttributionDataResponse(
                    attributionSource: "Error getting attribution data",
                    campaignData: nil,
                    deeplink: nil
                )
            }
        } catch {
            #if DEBUG
            print("GetAttributionData: Failed to fetch attribution data - Error: \(error)")
            #endif
            return LRAttributionDataResponse(
                attributionSource: "Error getting attribution data",
                campaignData: nil,
                deeplink: nil
            )
        }
    }
    
    // MARK: - Private Methods
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func initApiCall(token: String, source: String, link: String? = nil, debug: Bool? = false) async {
        let deviceDataDict = (await deviceData()).toDictionary()
        let installInstanceId = await getLinkRunnerInstallInstanceId()
        
        var requestData: SendableDictionary = [
            "token": token,
            "package_version": getPackageVersion(),
            "app_version": getAppVersion(),
            "device_data": deviceDataDict,
            "platform": "IOS",
            "source": source,
            "install_instance_id": installInstanceId,
            "debug": debug
        ]
        
        if let link = link {
            requestData["link"] = link
        }
        
        do {
            _ = try await makeRequest(
                endpoint: "/api/client/init",
                body: requestData
            )
            
            #if DEBUG
            print("Linkrunner: Initialization successful")
            #endif
            
        } catch {
            #if DEBUG
            print("Linkrunner: Init failed with error: \(error)")
            #endif
        }
    }
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func makeRequestWithoutRetry(endpoint: String, body: SendableDictionary) async throws -> SendableDictionary {
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
        
        // This will automatically handle signing if credentials are configured
        let (responseData, response) = try await requestInterceptor.signAndSendRequest(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkrunnerError.invalidResponse
        }
        
        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            throw LinkrunnerError.httpError(httpResponse.statusCode)
        }
        
        // Parse response without retry logic
        guard let jsonResponse = try JSONSerialization.jsonObject(with: responseData) as? SendableDictionary else {
            throw LinkrunnerError.jsonDecodingFailed
        }
        
        return jsonResponse
    }
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func makeRequest(endpoint: String, body: SendableDictionary) async throws -> SendableDictionary {
        return try await makeRequestWithRetry(endpoint: endpoint, body: body, attempt: 0)
    }
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func makeRequestWithRetry(endpoint: String, body: SendableDictionary, attempt: Int) async throws -> SendableDictionary {
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
        
        do {
            // This will automatically handle signing if credentials are configured
            let (responseData, response) = try await requestInterceptor.signAndSendRequest(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LinkrunnerError.invalidResponse
            }
            
            let statusCode = httpResponse.statusCode
            let shouldRetryHttp = (statusCode == 429) || (500...599).contains(statusCode)
            
            // Check for HTTP 500 errors that should trigger retry
            if shouldRetryHttp {
                if attempt < 4 {
                    #if DEBUG
                    print("Linkrunner: HTTP \(statusCode) on attempt \(attempt), retrying...")
                    #endif
                    return try await retryAfterDelay(endpoint: endpoint, body: body, attempt: attempt + 1)
                } else {
                    #if DEBUG
                    print("Linkrunner: HTTP \(statusCode) on final attempt \(attempt), failing")
                    #endif
                    throw LinkrunnerError.httpError(httpResponse.statusCode)
                }
            }
            
            if statusCode < 200 || statusCode >= 300 {
                throw LinkrunnerError.httpError(statusCode)
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                throw LinkrunnerError.jsonDecodingFailed
            }
            
            // Convert to SendableDictionary to ensure sendable compliance
            let sendableJson = json as SendableDictionary
            return sendableJson
            
        } catch {
            // Check if this is a retryable network error
            if isRetryableError(error) && attempt < 4 {
                #if DEBUG
                print("Linkrunner: Network error on attempt \(attempt), retrying... Error: \(error)")
                #endif
                return try await retryAfterDelay(endpoint: endpoint, body: body, attempt: attempt + 1)
            } else {
                #if DEBUG
                if attempt >= 4 {
                    print("Linkrunner: Network error on final attempt \(attempt), failing. Error: \(error)")
                } else {
                    print("Linkrunner: Non-retryable error: \(error)")
                }
                #endif
                throw error
            }
        }
    }
    
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func retryAfterDelay(endpoint: String, body: SendableDictionary, attempt: Int) async throws -> SendableDictionary {
        // Calculate exponential backoff delay: 2s, 4s, 8s for attempts 1, 2, 3
        // Initial trigger is 0th attempt, then 4 retry attempts
        // Formula: baseDelay * (2 ^ (attempt - 1))
        let baseDelay: TimeInterval = 2.0
        let delay = baseDelay * pow(2.0, Double(attempt - 1))
        
        #if DEBUG
        print("Linkrunner: Waiting \(delay) seconds before retry attempt \(attempt)")
        #endif
        
        // Task.sleep suspends the task for the specified duration
        // Task.sleep does not block the thread, other tasks can run on the same thread
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        return try await makeRequestWithRetry(endpoint: endpoint, body: body, attempt: attempt)
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        // Check for network connection errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .badServerResponse,
                 .resourceUnavailable:
                return true
            default:
                return false
            }
        }
        
        // Check for LinkrunnerError HTTP 500 (handled separately in makeRequestWithRetry)
        if let linkrunnerError = error as? LinkrunnerError {
            switch linkrunnerError {
            case .httpError(let code):
                return code == 500
            default:
                return false
            }
        }
        
        return false
    }
    
    private func getPackageVersion() -> String {
        return "3.3.0" // Swift package version
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
            
            // Advertising ID - only collect if disableIdfa is false
            if !self.disableIdfa {
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
            }
            
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
    
    // MARK: - App Install Time Tracking
    
    private static let APP_INSTALL_TIME_KEY = "linkrunner_app_install_time"
    
    private func getAppInstallTime() -> Date {
        // Check if we already have the install time stored
        if let storedTimestamp = UserDefaults.standard.object(forKey: LinkrunnerSDK.APP_INSTALL_TIME_KEY) as? Date {
            return storedTimestamp
        }
        
        // If not stored, use current time as install time and store it
        let installTime = Date()
        UserDefaults.standard.set(installTime, forKey: LinkrunnerSDK.APP_INSTALL_TIME_KEY)
        return installTime
    }
    
    private func getTimeSinceAppInstall() -> TimeInterval {
        print("Linkrunner: Getting time since app install")
        guard let installTime = appInstallTime else {
            return 0
        }
        return Date().timeIntervalSince(installTime)
    }
    
    // MARK: - SKAN Response Processing
    
    private func processSKANResponse(_ response: SendableDictionary, source: String) async {
        // Process SKAN data in background to avoid blocking main thread
        Task.detached(priority: .utility) {

            #if DEBUG
            print("LinkrunnerKit: Processing SKAN response from \(source)")
            print("LinkrunnerKit: Response: \(response)")
            #endif

            let response = response["data"] as? SendableDictionary ?? [:]
            // Extract SKAN conversion values from response
            guard let fineValue = response["fine_conversion_value"] as? Int else {
                return // No SKAN data in response
            }

            
            let coarseValue = response["coarse_conversion_value"] as? String
            let lockWindow = response["lock_postback"] as? Bool ?? false

            
            #if DEBUG
            print("LinkrunnerKit: Fine value: \(fineValue)")
            print("LinkrunnerKit: Coarse value: \(coarseValue)")
            print("LinkrunnerKit: Lock window: \(lockWindow)")
            print("LinkrunnerKit: Received SKAN values from \(source): fine=\(fineValue), coarse=\(coarseValue ?? "nil"), lock=\(lockWindow)")
            #endif
            
            // Update conversion value through SKAN service
            let success = await SKAdNetworkService.shared.updateConversionValue(
                fineValue: fineValue,
                coarseValue: coarseValue,
                lockWindow: lockWindow,
                source: source
            )
            
            #if DEBUG
            if success {
                print("LinkrunnerKit: Successfully updated SKAN conversion value from \(source)")
            } else {
                print("LinkrunnerKit: Failed to update SKAN conversion value from \(source)")
            }
            #endif
        }
    }
}