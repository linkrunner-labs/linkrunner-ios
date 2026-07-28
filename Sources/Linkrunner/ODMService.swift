import Foundation

/// Outcome of a single ODM fetch attempt. Carries no payload — the value itself is
/// returned separately and must never be logged or used as a metric label.
enum ODMFetchResult: String, Sendable {
    case success
    case empty
    case error
    case timeout
    /// Google's SDK is not present in the app.
    case unavailable
}

/// Diagnostics for one fetch attempt. Deliberately excludes the raw value.
struct ODMDiagnostics: Sendable {
    let available: Bool
    let result: ODMFetchResult
    let latencyMs: Int
}

/// Mirrors the part of Google's `ODCConversionManager` we use.
///
/// Declared locally rather than imported so LinkrunnerKit carries no build-time
/// dependency on `GoogleAdsOnDeviceConversion`. Selectors and the interaction enum are
/// taken verbatim from Google's shipped `ODCConversionManager.h` / `ODCConversionTypes.h`:
///
///     typedef NS_ENUM(NSInteger, ODCInteractionType) {
///       ODCInteractionTypeInstallation,   // 0
///       ODCInteractionTypeSessionStart,   // 1
///     };
///
///     @property(class, nonatomic, readonly) ODCConversionManager *sharedInstance;
///     - (void)setFirstLaunchTime:(NSDate *)firstLaunchTime;
///     - (void)fetchAggregateConversionInfoForInteraction:(ODCInteractionType)interaction
///                                             completion:(void (^)(NSString *_Nullable,
///                                                                  NSError *_Nullable))completion;
///
/// If Google renames any of these the failure is at runtime, not build time — hence the
/// `responds(to:)` checks before use, and the `odm_fetch_result` diagnostic.
@objc private protocol ODCConversionManaging {
    @objc(setFirstLaunchTime:)
    func setFirstLaunchTime(_ firstLaunchTime: Date)

    @objc(fetchAggregateConversionInfoForInteraction:completion:)
    func fetchAggregateConversionInfo(
        forInteraction interaction: Int,
        completion: @escaping (String?, Error?) -> Void
    )
}

/// Bridges to Google's On-Device Measurement SDK when the host app has linked it,
/// supplying the opaque `odm_info` value required by Integrated Conversion Measurement.
///
/// LinkrunnerKit does **not** depend on `GoogleAdsOnDeviceConversion`. The app adds it
/// — directly, or transitively via the Firebase iOS SDK — and this class finds it at
/// runtime. When it is absent every call is a no-op and `odm_info` is simply omitted.
///
/// This mirrors how Branch and Kochava integrate the same SDK, and it keeps the ~5 MB
/// static Google framework out of apps that do not use ICM.
@available(iOS 15.0, *)
final class ODMService: @unchecked Sendable {
    static let shared = ODMService()

    private let serialQueue = DispatchQueue(label: "com.linkrunner.odm", qos: .utility)

    /// Google's class name. Not renamed by Swift bridging — `NS_SWIFT_NAME(ConversionManager)`
    /// only affects the Swift-facing name, while the ObjC runtime keeps `ODCConversionManager`.
    private static let conversionManagerClassName = "ODCConversionManager"

    /// `ODCInteractionTypeInstallation`, the first case of `ODCInteractionType`.
    private static let interactionTypeInstallation = 0

    /// Cached values are scoped to an install instance so a reinstall never reuses
    /// the previous install's `odm_info`. See `cacheKey(for:)`.
    private static let ODM_INFO_KEY_PREFIX = "linkrunner_odm_info_"

    /// Holds the key of the currently-cached entry, so a superseded one can be removed
    /// without scanning every key in the domain. Deliberately outside
    /// `ODM_INFO_KEY_PREFIX` so it can never collide with a cache entry.
    private static let ODM_CURRENT_POINTER_KEY = "linkrunner_odm_current_key"

    private init() {}

    // MARK: - Availability

    /// Whether the host app has linked Google's ODM SDK.
    var isAvailable: Bool {
        return conversionManager() != nil
    }

    /// Resolves Google's shared conversion manager, or nil when the SDK is absent or its
    /// interface has changed.
    ///
    /// The `responds(to:)` checks matter: without a compile-time dependency, a renamed
    /// selector would otherwise surface as an unrecognised-selector crash inside the
    /// host app rather than a graceful no-op.
    private func conversionManager() -> ODCConversionManaging? {
        guard let managerClass = NSClassFromString(ODMService.conversionManagerClassName) as? NSObject.Type else {
            return nil
        }

        let sharedSelector = NSSelectorFromString("sharedInstance")
        guard managerClass.responds(to: sharedSelector),
              let boxed = managerClass.perform(sharedSelector),
              let instance = boxed.takeUnretainedValue() as? NSObject
        else {
            return nil
        }

        guard instance.responds(to: NSSelectorFromString("setFirstLaunchTime:")),
              instance.responds(to: NSSelectorFromString("fetchAggregateConversionInfoForInteraction:completion:"))
        else {
            return nil
        }

        // Google's class does not declare our locally-mirrored protocol, so a
        // conditional cast would fail. Dispatch through it instead — safe because
        // @objc protocol calls are plain objc_msgSend and every selector is verified above.
        return unsafeBitCast(instance, to: ODCConversionManaging.self)
    }

    // MARK: - First launch time

    /// Records the app's first launch time with Google. Must be called as early as
    /// possible and with an accurate timestamp — Google uses it for matching, so a
    /// drifted value degrades attribution quality.
    ///
    /// Callers pass Linkrunner's already-persisted install time so the value is
    /// stable across launches rather than being re-stamped each run. No-op when
    /// Google's SDK is not linked.
    func setFirstLaunchTime(_ date: Date) {
        conversionManager()?.setFirstLaunchTime(date)
    }

    // MARK: - Fetch

    /// Resolves `odm_info` for this install, preferring a cached value.
    ///
    /// Returns `nil` when Google's SDK is absent, returns empty, errors, or exceeds
    /// `timeout`. A `nil` result is never cached — a first-launch timeout is exactly
    /// the case worth retrying on a later launch.
    ///
    /// - Parameters:
    ///   - installInstanceId: scopes the cache entry to the current install.
    ///   - timeout: upper bound on how long the caller will wait. Google publishes no
    ///     latency figure, so this is our own bound, not a documented requirement.
    func resolveInfo(
        installInstanceId: String,
        timeout: TimeInterval
    ) async -> (info: String?, diagnostics: ODMDiagnostics) {
        if let cached = cachedInfo(installInstanceId: installInstanceId) {
            return (cached, ODMDiagnostics(available: true, result: .success, latencyMs: 0))
        }

        guard let manager = conversionManager() else {
            return (nil, ODMDiagnostics(available: false, result: .unavailable, latencyMs: 0))
        }

        let start = DispatchTime.now()
        let outcome = await fetchWithTimeout(manager, timeout: timeout)
        let latencyMs = Int((DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000)

        switch outcome {
        case .value(let info):
            cache(info, installInstanceId: installInstanceId)
            return (info, ODMDiagnostics(available: true, result: .success, latencyMs: latencyMs))
        case .empty:
            return (nil, ODMDiagnostics(available: true, result: .empty, latencyMs: latencyMs))
        case .failed:
            return (nil, ODMDiagnostics(available: true, result: .error, latencyMs: latencyMs))
        case .timedOut:
            return (nil, ODMDiagnostics(available: true, result: .timeout, latencyMs: latencyMs))
        }
    }

    // MARK: - Private

    private enum FetchOutcome: Sendable {
        case value(String)
        case empty
        case failed
        case timedOut
    }

    /// Races the fetch against a sleep. Google's completion handler is not
    /// cancellable, so when the timeout wins the losing task still resumes its
    /// continuation later — the group discards that result. Each continuation is
    /// resumed exactly once either way.
    private func fetchWithTimeout(
        _ manager: ODCConversionManaging,
        timeout: TimeInterval
    ) async -> FetchOutcome {
        await withTaskGroup(of: FetchOutcome.self) { group in
            group.addTask { await self.rawFetch(manager) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    private func rawFetch(_ manager: ODCConversionManaging) async -> FetchOutcome {
        await withCheckedContinuation { continuation in
            manager.fetchAggregateConversionInfo(
                forInteraction: ODMService.interactionTypeInstallation
            ) { info, error in
                if error != nil {
                    // Deliberately not logging the error object: it can embed the
                    // request context. Callers surface `odm_fetch_result` instead.
                    continuation.resume(returning: .failed)
                    return
                }
                guard let info = info, !info.isEmpty else {
                    continuation.resume(returning: .empty)
                    return
                }
                continuation.resume(returning: .value(info))
            }
        }
    }

    // MARK: - Cache

    private func cacheKey(for installInstanceId: String) -> String {
        return ODMService.ODM_INFO_KEY_PREFIX + installInstanceId
    }

    private func cachedInfo(installInstanceId: String) -> String? {
        let value = UserDefaults.standard.string(forKey: cacheKey(for: installInstanceId))
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    private func cache(_ info: String, installInstanceId: String) {
        serialQueue.async {
            let defaults = UserDefaults.standard
            let key = self.cacheKey(for: installInstanceId)

            // Drop the entry from a superseded install instance, so a reinstall doesn't
            // leave an orphaned value behind. Tracked by a single pointer key rather than
            // scanning UserDefaults, which would enumerate the whole domain.
            let previousKey = defaults.string(forKey: ODMService.ODM_CURRENT_POINTER_KEY)
            if let previousKey = previousKey, previousKey != key {
                defaults.removeObject(forKey: previousKey)
            }

            defaults.set(info, forKey: key)
            defaults.set(key, forKey: ODMService.ODM_CURRENT_POINTER_KEY)
        }
    }
}
