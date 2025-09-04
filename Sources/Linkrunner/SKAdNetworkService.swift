import Foundation
import StoreKit

@available(iOS 14.0, *)
public class SKAdNetworkService {
    public static let shared = SKAdNetworkService()
    
    // Thread safety
    private let serialQueue = DispatchQueue(label: "com.linkrunner.skan", qos: .utility)
    private var isUpdating = false
    
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
        print("LinkrunnerKit: Updating SKAN conversion value: fine=\(fineValue), coarse=\(coarseValue ?? "nil"), lock=\(lockWindow)")
        return await withCheckedContinuation { continuation in
            serialQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                // Prevent multiple simultaneous updates
                if self.isUpdating {
                    #if DEBUG
                    print("LinkrunnerKit: SKAN update already in progress, skipping")
                    #endif
                    continuation.resume(returning: false)
                    return
                }
                
                // Check if new value is lower than last updated value
                let lastFineValue = self.getLastConversionValue()
                print("LinkrunnerKit: Last conversion value: \(lastFineValue)")
                print("LinkrunnerKit: New conversion value: \(fineValue)")
                if fineValue < lastFineValue {
                    #if DEBUG
                    print("LinkrunnerKit: New conversion value (\(fineValue)) is lower than last value (\(lastFineValue)), skipping update")
                    #endif
                    continuation.resume(returning: false)
                    return
                }
                
                self.isUpdating = true
                
                #if DEBUG
                print("LinkrunnerKit: Updating SKAN conversion value: fine=\(fineValue), coarse=\(coarseValue ?? "nil"), lock=\(lockWindow)")
                #endif
                
                self.performSKANUpdate(
                    fineValue: fineValue,
                    coarseValue: coarseValue,
                    lockWindow: lockWindow,
                    source: source
                ) { result in
                    self.isUpdating = false
                    
                    if result.success {
                        self.saveLastConversionData(
                            fineValue: fineValue,
                            coarseValue: coarseValue,
                            lockWindow: lockWindow
                        )
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
        if #available(iOS 16.1, *) {
            // iOS 16.1+ supports all parameters
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
            0,
            coarseValue: .low,
            lockWindow: false
        ) { error in
            if let error = error {
                print(error)
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
