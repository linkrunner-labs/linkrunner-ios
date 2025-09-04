import Foundation
import StoreKit

// Import AdAttributionKit for iOS 17.4+
#if canImport(AdAttributionKit)
import AdAttributionKit
#endif

/// Attribution service that handles both modern AdAttributionKit (iOS 17.4+) and legacy SKAdNetwork (iOS 14.0+)
/// Automatically selects the appropriate API based on iOS version availability
@available(iOS 14.0, *)
public class SKAdNetworkService {
    public static let shared = SKAdNetworkService()
    
    // Thread safety
    private let serialQueue = DispatchQueue(label: "com.linkrunner.skan", qos: .utility)
    
    // Storage keys
    private static let LAST_CONVERSION_VALUE_KEY = "linkrunner_last_conversion_value"
    private static let LAST_COARSE_VALUE_KEY = "linkrunner_last_coarse_value"
    private static let LAST_LOCK_WINDOW_KEY = "linkrunner_last_lock_window"
    private static let SKAN_REGISTER_TIMESTAMP_KEY = "linkrunner_skan_register_timestamp"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Register initial conversion value (0/low) on first app install
    public func registerInitialConversionValue() async {
        await withCheckedContinuation { continuation in
            serialQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // Check if we've already registered
                if self.hasRegisteredBefore() {
                    continuation.resume()
                    return
                }
                
                #if DEBUG
                print("LinkrunnerKit: Registering initial SKAN conversion value (0/low)")
                #endif
                
                self.performSKANRegistration(
                    fineValue: 0,
                    coarseValue: "low",
                    lockWindow: false,
                    source: "sdk_init"
                ) { result in
                    if result.success {
                        self.markAsRegistered()
                        self.saveLastConversionData(
                            fineValue: 0,
                            coarseValue: "low",
                            lockWindow: false
                        )
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    /// Update conversion value from API response
    public func updateConversionValue(
        fineValue: Int,
        coarseValue: String?,
        lockWindow: Bool,
        source: String = "api"
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            serialQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                #if DEBUG
                print("LinkrunnerKit: Processing SKAN update for \(source): fine=\(fineValue)")
                #endif
                
                // Check if new value is lower than last updated value
                let lastFineValue = self.getLastConversionValue()
                if fineValue < lastFineValue {
                    #if DEBUG
                    print("LinkrunnerKit: New conversion value (\(fineValue)) is lower than last value (\(lastFineValue)), skipping update for \(source)")
                    #endif
                    continuation.resume(returning: false)
                    return
                }
                
                // Check if this exact same value is already the current value
                if fineValue == lastFineValue {
                    let lastCoarseValue = self.getLastCoarseValue()
                    let lastLockWindow = self.getLastLockWindow()
                    if coarseValue == lastCoarseValue && lockWindow == lastLockWindow {
                        #if DEBUG
                        print("LinkrunnerKit: Same conversion value (\(fineValue)) already set, skipping update for \(source)")
                        #endif
                        continuation.resume(returning: true) // Return true since it's already at the desired state
                        return
                    }
                }
                
                #if DEBUG
                print("LinkrunnerKit: Executing SKAN update for \(source): fine=\(fineValue), coarse=\(coarseValue ?? "nil"), lock=\(lockWindow)")
                #endif
                
                self.performSKANUpdate(
                    fineValue: fineValue,
                    coarseValue: coarseValue,
                    lockWindow: lockWindow,
                    source: source
                ) { result in
                    if result.success {
                        self.saveLastConversionData(
                            fineValue: fineValue,
                            coarseValue: coarseValue,
                            lockWindow: lockWindow
                        )
                        #if DEBUG
                        print("LinkrunnerKit: Successfully updated SKAN conversion value for \(source)")
                        #endif
                    } else {
                        #if DEBUG
                        print("LinkrunnerKit: Failed to update SKAN conversion value for \(source): \(result.error ?? "Unknown error")")
                        #endif
                    }
                    
                    continuation.resume(returning: result.success)
                }
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func hasRegisteredBefore() -> Bool {
        return UserDefaults.standard.object(forKey: SKAdNetworkService.SKAN_REGISTER_TIMESTAMP_KEY) != nil
    }
    
    private func markAsRegistered() {
        UserDefaults.standard.set(Date(), forKey: SKAdNetworkService.SKAN_REGISTER_TIMESTAMP_KEY)
    }
    
    private func getLastConversionValue() -> Int {
        return UserDefaults.standard.integer(forKey: SKAdNetworkService.LAST_CONVERSION_VALUE_KEY)
    }
    
    private func getLastCoarseValue() -> String? {
        return UserDefaults.standard.string(forKey: SKAdNetworkService.LAST_COARSE_VALUE_KEY)
    }
    
    private func getLastLockWindow() -> Bool {
        return UserDefaults.standard.bool(forKey: SKAdNetworkService.LAST_LOCK_WINDOW_KEY)
    }
    
    private func saveLastConversionData(fineValue: Int, coarseValue: String?, lockWindow: Bool) {
        UserDefaults.standard.set(fineValue, forKey: SKAdNetworkService.LAST_CONVERSION_VALUE_KEY)
        if let coarseValue = coarseValue {
            UserDefaults.standard.set(coarseValue, forKey: SKAdNetworkService.LAST_COARSE_VALUE_KEY)
        }
        UserDefaults.standard.set(lockWindow, forKey: SKAdNetworkService.LAST_LOCK_WINDOW_KEY)
    }
    
    // MARK: - SKAdNetwork API Calls
    
    private func performSKANRegistration(
        fineValue: Int,
        coarseValue: String,
        lockWindow: Bool,
        source: String,
        completion: @escaping (SKANResult) -> Void
    ) {
        #if canImport(AdAttributionKit)
        if #available(iOS 17.4, *) {
            // iOS 17.4+ use AdAttributionKit for registration
            self.updateWithAdAttributionKit(
                fineValue: fineValue,
                coarseValue: coarseValue,
                lockWindow: lockWindow,
                completion: completion
            )
            return
        }
        #endif
        
        if #available(iOS 16.1, *) {
            // iOS 16.1+ supports coarse value and lock window in registration
            self.registerWithCoarseValue(
                fineValue: fineValue,
                coarseValue: coarseValue,
                lockWindow: lockWindow,
                completion: completion
            )
        } else if #available(iOS 15.4, *) {
            // iOS 15.4+ supports completion handler
            self.registerWithCompletionHandler(
                fineValue: fineValue,
                completion: completion
            )
        } else {
            // iOS 14.0+ basic registration
            self.registerBasic(completion: completion)
        }
    }
    
    private func performSKANUpdate(
        fineValue: Int,
        coarseValue: String?,
        lockWindow: Bool,
        source: String,
        completion: @escaping (SKANResult) -> Void
    ) {
        #if canImport(AdAttributionKit)
        if #available(iOS 17.4, *) {
            // iOS 17.4+ use AdAttributionKit (modern approach)
            self.updateWithAdAttributionKit(
                fineValue: fineValue,
                coarseValue: coarseValue,
                lockWindow: lockWindow,
                completion: completion
            )
            return
        }
        #endif
        
        if #available(iOS 16.1, *) {
            // iOS 16.1+ supports all parameters with SKAdNetwork
            if let coarseValue = coarseValue {
                self.updateWithCoarseValue(
                    fineValue: fineValue,
                    coarseValue: coarseValue,
                    lockWindow: lockWindow,
                    completion: completion
                )
            } else {
                self.updateWithCompletionHandler(
                    fineValue: fineValue,
                    completion: completion
                )
            }
        } else if #available(iOS 15.4, *) {
            // iOS 15.4+ supports completion handler
            self.updateWithCompletionHandler(
                fineValue: fineValue,
                completion: completion
            )
        } else {
            // iOS 14.0+ basic update
            self.updateBasic(fineValue: fineValue, completion: completion)
        }
    }
    
    // MARK: - iOS Version-Specific Implementations
    
    @available(iOS 16.1, *)
    private func registerWithCoarseValue(
        fineValue: Int,
        coarseValue: String,
        lockWindow: Bool,
        completion: @escaping (SKANResult) -> Void
    ) {
        guard let skanCoarseValue = mapCoarseValue(coarseValue) else {
            completion(SKANResult(success: false, error: "Invalid coarse value: \(coarseValue)"))
            return
        }
        
        SKAdNetwork.updatePostbackConversionValue(
            fineValue,
            coarseValue: skanCoarseValue,
            lockWindow: lockWindow
        ) { error in
            if let error = error {
                completion(SKANResult(success: false, error: error.localizedDescription))
            } else {
                completion(SKANResult(success: true, error: nil))
            }
        }
    }
    
    @available(iOS 16.1, *)
    private func updateWithCoarseValue(
        fineValue: Int,
        coarseValue: String,
        lockWindow: Bool,
        completion: @escaping (SKANResult) -> Void
    ) {
        guard let skanCoarseValue = mapCoarseValue(coarseValue) else {
            completion(SKANResult(success: false, error: "Invalid coarse value: \(coarseValue)"))
            return
        }
        
        SKAdNetwork.updatePostbackConversionValue(
            fineValue,
            coarseValue: skanCoarseValue,
            lockWindow: lockWindow
        ) { error in
            if let error = error {
                completion(SKANResult(success: false, error: error.localizedDescription))
            } else {
                completion(SKANResult(success: true, error: nil))
            }
        }
    }
    
    @available(iOS 15.4, *)
    private func registerWithCompletionHandler(
        fineValue: Int,
        completion: @escaping (SKANResult) -> Void
    ) {
        SKAdNetwork.updatePostbackConversionValue(fineValue) { error in
            if let error = error {
                completion(SKANResult(success: false, error: error.localizedDescription))
            } else {
                completion(SKANResult(success: true, error: nil))
            }
        }
    }
    
    @available(iOS 15.4, *)
    private func updateWithCompletionHandler(
        fineValue: Int,
        completion: @escaping (SKANResult) -> Void
    ) {
        SKAdNetwork.updatePostbackConversionValue(fineValue) { error in
            if let error = error {
                completion(SKANResult(success: false, error: error.localizedDescription))
            } else {
                completion(SKANResult(success: true, error: nil))
            }
        }
    }
    
    @available(iOS 14.0, *)
    private func registerBasic(completion: @escaping (SKANResult) -> Void) {
        SKAdNetwork.registerAppForAdNetworkAttribution()
        // Basic registration doesn't provide completion callback
        completion(SKANResult(success: true, error: nil))
    }
    
    @available(iOS 14.0, *)
    private func updateBasic(fineValue: Int, completion: @escaping (SKANResult) -> Void) {
        SKAdNetwork.updateConversionValue(fineValue)
        // Basic update doesn't provide completion callback
        completion(SKANResult(success: true, error: nil))
    }
    
    // MARK: - AdAttributionKit Implementation (iOS 17.4+)
    
    #if canImport(AdAttributionKit)
    @available(iOS 17.4, *)
    private func updateWithAdAttributionKit(
        fineValue: Int,
        coarseValue: String?,
        lockWindow: Bool,
        completion: @escaping (SKANResult) -> Void
    ) {
        Task {
            do {
                // Map coarse value for AdAttributionKit
                var adKitCoarseValue: AdAttributionKit.CoarseConversionValue?
                if let coarseValue = coarseValue {
                    adKitCoarseValue = self.mapAdKitCoarseValue(coarseValue)
                }
                
                #if DEBUG
                print("LinkrunnerKit: Using AdAttributionKit to update conversion value: fine=\(fineValue), coarse=\(coarseValue ?? "nil"), lock=\(lockWindow)")
                #endif
                
                // Update conversion value using AdAttributionKit
                try await Postback.updateConversionValue(
                    fineValue,
                    coarseConversionValue: adKitCoarseValue ?? .low,
                    lockPostback: lockWindow
                )
                
                completion(SKANResult(success: true, error: nil))
            } catch {
                #if DEBUG
                print("LinkrunnerKit: AdAttributionKit update failed: \(error.localizedDescription)")
                #endif
                completion(SKANResult(success: false, error: error.localizedDescription))
            }
        }
    }
    
    @available(iOS 17.4, *)
    private func mapAdKitCoarseValue(_ value: String) -> AdAttributionKit.CoarseConversionValue {
        switch value.lowercased() {
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        default:
            return .low
        }
    }
    #endif
    
    // MARK: - Helper Methods
    
    @available(iOS 16.1, *)
    private func mapCoarseValue(_ value: String) -> SKAdNetwork.CoarseConversionValue? {
        switch value.lowercased() {
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        default:
            return nil
        }
    }
}

// MARK: - Result Types

struct SKANResult {
    let success: Bool
    let error: String?
}
