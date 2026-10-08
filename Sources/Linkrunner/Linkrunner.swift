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

#if canImport(AdServices)
import AdServices
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
        /// Hardware model identifier, e.g. "iPhone17,3". Distinct from `device`, which
        /// is the generic family string ("iPhone") that UIDevice reports. Google's
        /// User-Agent spec requires the identifier form, and it cannot be derived
        /// server-side from anything else in the payload.
        var deviceModelIdentifier: String?
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
        var adservicesAttributionToken: String?
        /// Opaque Google ODM value. Never logged.
        var odmInfo: String?
        /// Seconds since epoch, microsecond precision, matching Google's `fot` contract.
        var firstOpenTimestamp: Double?
        var attStatus: String?
        var consent: LinkrunnerConsent?

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
            
            if let deviceModelIdentifier = deviceModelIdentifier { dict["device_model"] = deviceModelIdentifier }
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
            if let adservicesAttributionToken = adservicesAttributionToken { dict["adservices_attribution_token"] = adservicesAttributionToken }
            if let odmInfo = odmInfo { dict["odm_info"] = odmInfo }
            if let firstOpenTimestamp = firstOpenTimestamp { dict["first_open_timestamp"] = firstOpenTimestamp }
            if let attStatus = attStatus { dict["att_status"] = attStatus }
            if let consent = consent, !consent.isEmpty { dict["consent"] = consent.toDictionary() }

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

    // Google Ads consent, supplied by the host app's CMP. Restored from storage in init
    // so a returning user keeps their state without the app re-supplying it. Defaults to
    // all-unknown, reported as "not known" rather than assumed permissive.
    //
    // Assigned eagerly rather than `lazy`: this is read from `deviceData()` on every
    // request, and Swift's lazy initialization is not atomic, so concurrent API calls
    // could enter the initializer at once.
    private var consent: LinkrunnerConsent

    /// When enabled, consent is read from an IAB TCF CMP's `IABTCF_*` keys for any
    /// signal the app has not set explicitly. Opt-in — see `enableTCFConsentCollection`.
    private var tcfConsentCollectionEnabled = false

    /// Resolved once during `initialize` and reused for every subsequent payload.
    /// Never logged — see ODMService.
    private var odmInfo: String?

    /// AdServices attribution token, cached for the process. Previously re-fetched on
    /// every request, which meant a synchronous `AAAttribution.attributionToken()` call
    /// on each network call rather than once per install.
    private var cachedAttributionToken: String?

    /// Hardware model identifier, resolved once. `deviceData()` runs on every request
    /// and the hardware cannot change mid-process, so there is no reason to call
    /// `uname` more than once.
    private let deviceModelIdentifier: String? = LinkrunnerSDK.readDeviceModelIdentifier()

    /// Upper bound on the ODM fetch during `initialize`. Google publishes no latency
    /// figure; this is our own bound, and should be tuned from measured p95.
    private static let ODM_FETCH_TIMEOUT: TimeInterval = 5.0
    
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
        self.consent = LinkrunnerSDK.loadPersistedConsent()
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
    
    /// Set the Google Ads consent state.
    ///
    /// Call it before `initialize` so the first payload carries the correct state, and
    /// call it again whenever your CMP state changes — the new values replace the old
    /// ones and apply to every subsequent payload.
    ///
    /// The values are persisted, so a returning user keeps their consent state without
    /// the app having to re-supply it on every launch. Anything left `.unknown` is
    /// reported as unknown rather than assumed granted, and is omitted from the payload.
    ///
    /// - Parameter consent: consent signals from your Consent Management Platform.
    ///   See ``LinkrunnerConsent`` for what each signal means.
    public func setConsent(_ consent: LinkrunnerConsent) {
        guard consent != self.consent else { return }
        self.consent = consent
        persistConsent(consent)
    }

    /// Collect Google Ads consent automatically from an IAB TCF v2.2/2.3 Consent
    /// Management Platform.
    ///
    /// When enabled, the SDK reads the CMP's standard `IABTCF_*` keys and derives
    /// `isEEA`, `hasConsentForDataUsage` and `hasConsentForAdsPersonalization`
    /// using Google's published TCF mapping. Call it before `initialize` so the first
    /// payload carries consent.
    ///
    /// Anything set explicitly via `setConsent` takes precedence over the TCF value,
    /// per signal — so you can let the CMP supply most of it and override one field.
    /// Signals the CMP has not written stay `.unknown` and are omitted from the payload.
    ///
    /// This is opt-in rather than automatic because interpreting a TC string on your
    /// behalf is a legal judgement. Only enable it if you use a TCF-compliant CMP;
    /// custom consent screens and Firebase Consent Mode do not write these keys.
    ///
    /// - Parameter enabled: whether to read consent from the TCF CMP
    public func enableTCFConsentCollection(_ enabled: Bool = true) {
        self.tcfConsentCollectionEnabled = enabled
    }

    /// Merges explicitly-set consent over TCF-derived consent, per signal.
    ///
    /// Read fresh on every payload rather than snapshotted at init: on first launch the
    /// CMP may not have resolved yet, so an early read would pin `.unknown` for the
    /// life of the process.
    private func resolveConsent() -> LinkrunnerConsent {
        guard tcfConsentCollectionEnabled else { return consent }

        let tcf = TCFConsent.read()
        // Explicit values win; fall back to TCF only where the app said nothing.
        return LinkrunnerConsent(
            isEEA: consent.isEEA == .unknown ? tcf.isEEA : consent.isEEA,
            hasConsentForDataUsage: consent.hasConsentForDataUsage == .unknown ? tcf.hasConsentForDataUsage : consent.hasConsentForDataUsage,
            hasConsentForAdsPersonalization: consent.hasConsentForAdsPersonalization == .unknown
                ? tcf.hasConsentForAdsPersonalization
                : consent.hasConsentForAdsPersonalization
        )
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

            // Hand Google the same persisted install time Linkrunner already uses, so
            // the value is stable across launches instead of drifting each run.
            // Must happen before any conversion info is fetched.
            if let appInstallTime = appInstallTime {
                ODMService.shared.setFirstLaunchTime(appInstallTime)
            }

            // Initialize SKAN with default values (0/low) on first init
            await SKAdNetworkService.shared.registerInitialConversionValue()
        }

        // Resolve Google ODM before the init call, since that request is what the
        // backend forwards as `first_open`. Bounded, and never fatal: on empty,
        // error or timeout we omit `odm_info` and carry on. Initialization must
        // never permanently depend on Google being reachable.
        await resolveODMInfo()

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

        setUserId(userData.id)

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

        setUserId(userData.id)

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

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func setCustomerUserId(_ userId: String) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: setCustomerUserId failed - SDK not initialized")
            #endif
            return
        }

        if userId.isEmpty {
            #if DEBUG
            print("Linkrunner: setCustomerUserId failed - userId is empty")
            #endif
            return
        }

        if let existing = getUserId(), existing == userId {
            return
        }

        setUserId(userId)

        let requestData: SendableDictionary = [
            "token": token,
            "user_id": userId,
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]

        do {
            _ = try await makeRequest(
                endpoint: "/api/client/customer-user-id",
                body: requestData
            )
        } catch {
            #if DEBUG
            print("Linkrunner: setCustomerUserId failed with error: \(error)")
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
    ///   - eventId: Optional unique identifier to deduplicate events server-side
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func trackEvent(eventName: String, eventData: SendableDictionary? = nil, eventId: String? = nil) async {
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
        
        var requestData: SendableDictionary = [
            "token": token,
            "event_name": eventName,
            "event_data": eventData as Any,
            "device_data": (await deviceData()).toDictionary(),
            "install_instance_id": await getLinkRunnerInstallInstanceId(),
            "time_since_app_install": getTimeSinceAppInstall(),
            "platform": "IOS"
        ]
        
        if let eventId = eventId, !eventId.isEmpty {
            requestData["event_id"] = eventId
        }

        if let userId = getUserId(), !userId.isEmpty {
            requestData["user_id"] = userId
        }

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
    ///   - paymentId: Payment identifier (required)
    ///   - type: Optional payment type
    ///   - status: Optional payment status
    ///   - eventData: Optional event data
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func capturePayment(
        amount: Double,
        userId: String,
        paymentId: String,
        type: PaymentType = .default,
        status: PaymentStatus = .completed,
        eventData: SendableDictionary? = nil
    ) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: capturePayment failed - SDK not initialized")
            #endif
            return
        }

        guard !paymentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            #if DEBUG
            print("Linkrunner: capturePayment failed - paymentId is required")
            #endif
            return
        }

        let resolvedUserId = userId.isEmpty ? (getUserId() ?? "") : userId

        var requestData: SendableDictionary = [
            "token": token,
            "user_id": resolvedUserId,
            "platform": "IOS",
            "amount": amount,
            "event_data": eventData as Any,
            "install_instance_id": await getLinkRunnerInstallInstanceId(),
            "time_since_app_install": getTimeSinceAppInstall(),
            "payment_id": paymentId,
        ]

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
                "paymentId": paymentId,
                "userId": resolvedUserId,
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
    
    /// Update the push notification token for the current user
    /// - Parameter pushToken: The push notification token to be associated with the user
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func setPushToken(_ pushToken: String) async {
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: setPushToken failed - SDK not initialized")
            #endif
            return
        }
        
        if pushToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            #if DEBUG
            print("Linkrunner: setPushToken failed - Push token cannot be empty")
            #endif
            return
        }
        
        let requestData: SendableDictionary = [
            "token": token,
            "push_token": pushToken,
            "platform": "IOS",
            "install_instance_id": await getLinkRunnerInstallInstanceId()
        ]
        
        do {
            _ = try await makeRequest(
                endpoint: "/api/client/update-push-token",
                body: requestData
            )
            
            #if DEBUG
            print("Linkrunner: Push token updated successfully")
            #endif
        } catch {
            #if DEBUG
            print("Linkrunner: setPushToken failed with error: \(error)")
            #endif
        }
    }
    
    /// Fetches attribution data for the current installation
    /// - Returns: The attribution data response
    /// to ensure backward compatibility we return empty LRAttributionDataResponse on error
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
    
    /// Handle a deeplink for re-engagement attribution.
    /// Call this method when the app is opened via a deeplink, regardless of app state.
    /// - Parameter url: The full deeplink URL that opened the app
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    public func handleDeeplink(url: String?) async -> LRDeeplinkResponse {
        guard let deeplinkUrl = url, !deeplinkUrl.isEmpty else {
            #if DEBUG
            print("Linkrunner: handleDeeplink called with nil or empty URL, ignoring")
            #endif
            return LRDeeplinkResponse(deeplink: nil, isLinkrunner: false)
        }
        
        guard let token = self.token else {
            #if DEBUG
            print("Linkrunner: handleDeeplink failed - SDK not initialized. Call initialize() first.")
            #endif
            return LRDeeplinkResponse(deeplink: url, isLinkrunner: false)
        }
        
        #if DEBUG
        print("Linkrunner: handleDeeplink called.")
        #endif
        
        let deviceDataDict = (await deviceData()).toDictionary()
        let installInstanceId = await getLinkRunnerInstallInstanceId()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        let requestData: SendableDictionary = [
            "token": token,
            "platform": "IOS",
            "install_instance_id": installInstanceId,
            "deeplink_url": deeplinkUrl,
            "device_data": deviceDataDict,
            "timestamp": timestamp
        ]
        
        do {
            let response = try await makeRequest(
                endpoint: "/api/client/handle-deeplink",
                body: requestData
            )
            
            #if DEBUG
            print("Linkrunner: handleDeeplink successful")
            #endif
            
            // Process SKAN conversion values from response if present
            await processSKANResponse(response, source: "deeplink")
            
            if let data = response["data"] as? SendableDictionary {
                return LRDeeplinkResponse(dictionary: data)
            } else {
                #if DEBUG
                print("Linkrunner: handleDeeplink - Invalid response data")
                #endif
                return LRDeeplinkResponse(deeplink: deeplinkUrl, isLinkrunner: false)
            }
            
        } catch {
            #if DEBUG
            print("Linkrunner: handleDeeplink failed with error: \(error)")
            #endif
            return LRDeeplinkResponse(deeplink: deeplinkUrl, isLinkrunner: false)
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
    
    /// Resolve the Google ODM value for this install, if one is available.
    ///
    /// Only fetches when we don't already hold a value, so this is effectively
    /// once-per-install: `ODMService` caches successes against the install instance
    /// and failures are left uncached so a later launch can retry.
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    private func resolveODMInfo() async {
        guard odmInfo == nil else { return }

        let installInstanceId = await getLinkRunnerInstallInstanceId()
        let (info, diagnostics) = await ODMService.shared.resolveInfo(
            installInstanceId: installInstanceId,
            timeout: LinkrunnerSDK.ODM_FETCH_TIMEOUT
        )
        odmInfo = info

        #if DEBUG
        // Diagnostics only. The raw value must never be logged, in any build.
        print("Linkrunner: odm_available=\(diagnostics.available) "
              + "odm_fetch_result=\(diagnostics.result.rawValue) "
              + "odm_fetch_latency_ms=\(diagnostics.latencyMs)")

        // TEMP DEBUG ONLY — remove before committing. Logs the raw odm_info value,
        // which this SDK otherwise deliberately never logs (see comments above).
        print("Linkrunner [TEMP DEBUG]: raw odm_info=\(info ?? "nil")")
        #endif
    }

    /// Get attribution token from AdServices framework
    ///
    /// Cached for the process: `AAAttribution.attributionToken()` is a synchronous
    /// call and this runs from `deviceData()`, which every request builds. Fetching
    /// it per request meant repeating that work on every event and payment call.
    /// A nil result is not cached, so a token that isn't ready yet is retried.
    /// - Returns: Attribution token string if available, nil otherwise
    private func getAttributionToken() async -> String? {
        if let cachedAttributionToken = cachedAttributionToken {
            return cachedAttributionToken
        }
        #if canImport(AdServices)
        do {
            let token = try AAAttribution.attributionToken()
            cachedAttributionToken = token
            return token
        } catch {
            #if DEBUG
            print("Linkrunner: Failed to get attribution token: \(error)")
            #endif
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Hardware model identifier, e.g. "iPhone17,3".
    ///
    /// `UIDevice.current.model` only returns the generic family ("iPhone"), which is not
    /// enough for Google's App Conversion API User-Agent — its spec calls for the
    /// identifier form (`iPhone9,1`). Read from `uname` since there is no UIKit API for it.
    ///
    /// On the simulator `uname` reports the host architecture (`arm64`/`x86_64`), so we
    /// prefer the simulator's own model identifier to keep test payloads meaningful.
    private static func readDeviceModelIdentifier() -> String? {
        if let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulatorModel.isEmpty {
            return simulatorModel
        }

        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return nil }

        let identifier = withUnsafeBytes(of: &systemInfo.machine) { rawBuffer -> String? in
            let bytes = rawBuffer.prefix { $0 != 0 }
            return String(bytes: bytes, encoding: .utf8)
        }

        guard let identifier = identifier, !identifier.isEmpty else { return nil }
        return identifier
    }

    /// Current App Tracking Transparency authorization.
    ///
    /// Sent as Apple's raw enum value (0 notDetermined, 1 restricted, 2 denied,
    /// 3 authorized) because that is the established `att_status` wire contract —
    /// the backend compares against "3" when resolving tracking consent. Do not
    /// switch this to a descriptive string without changing the consumers.
    ///
    /// Reported separately from consent: ATT governs IDFA access and is not
    /// equivalent to Google's ad user data or ad personalization signals.
    private func getATTStatus() -> String? {
        #if canImport(AppTrackingTransparency)
        return String(ATTrackingManager.trackingAuthorizationStatus.rawValue)
        #else
        return nil
        #endif
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
        
        return false
    }
    
    private func getPackageVersion() -> String {
        return "4.2.0" // Swift package version
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
            
            // Attribution token from AdServices
            let attributionToken = await getAttributionToken()
            
            return DeviceData(
                device: deviceModel,
                deviceModelIdentifier: self.deviceModelIdentifier,
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
                installInstanceId: installInstanceId,
                adservicesAttributionToken: attributionToken,
                odmInfo: self.odmInfo,
                firstOpenTimestamp: (self.appInstallTime ?? self.getAppInstallTime()).timeIntervalSince1970,
                attStatus: self.getATTStatus(),
                consent: self.resolveConsent()
            )
#else
            // Fallback for non-UIKit platforms
            // Attribution token from AdServices
            let attributionToken = await getAttributionToken()
            
            return DeviceData(
                device: "Unknown",
                deviceModelIdentifier: self.deviceModelIdentifier,
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
                installInstanceId: await getLinkRunnerInstallInstanceId(),
                adservicesAttributionToken: attributionToken,
                odmInfo: self.odmInfo,
                firstOpenTimestamp: (self.appInstallTime ?? self.getAppInstallTime()).timeIntervalSince1970,
                attStatus: self.getATTStatus(),
                consent: self.resolveConsent()
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
    
    private static let USER_ID_STORAGE_KEY = "linkrunner_user_id"

    private func setUserId(_ userId: String?) {
        KeychainHelper.set(userId, forKey: LinkrunnerSDK.USER_ID_STORAGE_KEY)
    }

    private func getUserId() -> String? {
        return KeychainHelper.get(forKey: LinkrunnerSDK.USER_ID_STORAGE_KEY)
    }

    private func setDeeplinkURL(_ deeplinkURL: String) async {
        UserDefaults.standard.set(deeplinkURL, forKey: LinkrunnerSDK.DEEPLINK_URL_STORAGE_KEY)
    }
    
    private func getDeeplinkURL() async throws -> String? {
        return UserDefaults.standard.string(forKey: LinkrunnerSDK.DEEPLINK_URL_STORAGE_KEY)
    }
    
    // MARK: - Consent Storage

    private static let CONSENT_IS_EEA_KEY = "linkrunner_consent_is_eea"
    private static let CONSENT_AD_USER_DATA_KEY = "linkrunner_consent_ad_user_data"
    private static let CONSENT_AD_PERSONALIZATION_KEY = "linkrunner_consent_ad_personalization"

    /// Reads consent stored by a previous session. Missing keys read back as `.unknown`,
    /// so an app that has never called `setConsent` is reported as unknown, not granted.
    fileprivate static func loadPersistedConsent() -> LinkrunnerConsent {
        let defaults = UserDefaults.standard
        func status(_ key: String) -> ConsentStatus {
            guard let raw = defaults.string(forKey: key) else { return .unknown }
            return ConsentStatus(rawValue: raw) ?? .unknown
        }
        return LinkrunnerConsent(
            isEEA: status(CONSENT_IS_EEA_KEY),
            hasConsentForDataUsage: status(CONSENT_AD_USER_DATA_KEY),
            hasConsentForAdsPersonalization: status(CONSENT_AD_PERSONALIZATION_KEY)
        )
    }

    /// Persists the full triple, replacing whatever was stored before.
    ///
    /// `.unknown` is written out rather than skipped: if an app moves a signal back to
    /// unknown, leaving the old value on disk would keep reporting a choice the user
    /// no longer has.
    fileprivate func persistConsent(_ consent: LinkrunnerConsent) {
        let defaults = UserDefaults.standard
        defaults.set(consent.isEEA.rawValue, forKey: LinkrunnerSDK.CONSENT_IS_EEA_KEY)
        defaults.set(consent.hasConsentForDataUsage.rawValue, forKey: LinkrunnerSDK.CONSENT_AD_USER_DATA_KEY)
        defaults.set(consent.hasConsentForAdsPersonalization.rawValue, forKey: LinkrunnerSDK.CONSENT_AD_PERSONALIZATION_KEY)
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
