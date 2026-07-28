import Foundation

#if canImport(GoogleAdsOnDeviceConversion)
import GoogleAdsOnDeviceConversion
#endif

/// Outcome of a single ODM fetch attempt. Carries no payload — the value itself is
/// returned separately and must never be logged or used as a metric label.
public enum ODMFetchResult: String, Sendable {
    case success
    case empty
    case error
    case timeout
    case unavailable
}

/// Diagnostics for one fetch attempt. Deliberately excludes the raw value.
public struct ODMDiagnostics: Sendable {
    public let available: Bool
    public let result: ODMFetchResult
    public let latencyMs: Int
}

/// Wraps Google's On-Device Measurement SDK, which supplies the opaque `odm_info`
/// value required by Google Integrated Conversion Measurement on iOS.
///
/// ODM is region-gated to the EEA, UK and Switzerland; elsewhere it returns an empty
/// value and callers simply omit the field. It requires neither ATT authorization
/// nor IDFA.
@available(iOS 15.0, *)
final class ODMService: @unchecked Sendable {
    static let shared = ODMService()

    private let serialQueue = DispatchQueue(label: "com.linkrunner.odm", qos: .utility)

    /// Cached values are scoped to an install instance so a reinstall never reuses
    /// the previous install's `odm_info`. See `cacheKey(for:)`.
    private static let ODM_INFO_KEY_PREFIX = "linkrunner_odm_info_"

    private init() {}

    // MARK: - First launch time

    /// Records the app's first launch time with Google. Must be called as early as
    /// possible and with an accurate timestamp — Google uses it for matching, so a
    /// drifted value degrades attribution quality.
    ///
    /// Callers pass Linkrunner's already-persisted install time so the value is
    /// stable across launches rather than being re-stamped each run.
    func setFirstLaunchTime(_ date: Date) {
        #if canImport(GoogleAdsOnDeviceConversion)
        ConversionManager.sharedInstance.setFirstLaunchTime(date)
        #endif
    }

    // MARK: - Fetch

    /// Resolves `odm_info` for this install, preferring a cached value.
    ///
    /// Returns `nil` when ODM is unavailable, returns empty, errors, or exceeds
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

        #if canImport(GoogleAdsOnDeviceConversion)
        let start = DispatchTime.now()
        let outcome = await fetchWithTimeout(timeout)
        let latencyMs = Int((DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000)

        switch outcome {
        case .value(let info):
            cache(info, installInstanceId: installInstanceId)
            return (info, ODMDiagnostics(available: true, result: .success, latencyMs: latencyMs))
        case .empty:
            return (nil, ODMDiagnostics(available: false, result: .empty, latencyMs: latencyMs))
        case .failed:
            return (nil, ODMDiagnostics(available: false, result: .error, latencyMs: latencyMs))
        case .timedOut:
            return (nil, ODMDiagnostics(available: false, result: .timeout, latencyMs: latencyMs))
        }
        #else
        return (nil, ODMDiagnostics(available: false, result: .unavailable, latencyMs: 0))
        #endif
    }

    // MARK: - Private

    #if canImport(GoogleAdsOnDeviceConversion)
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
    private func fetchWithTimeout(_ timeout: TimeInterval) async -> FetchOutcome {
        await withTaskGroup(of: FetchOutcome.self) { group in
            group.addTask { await self.rawFetch() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    private func rawFetch() async -> FetchOutcome {
        await withCheckedContinuation { continuation in
            ConversionManager.sharedInstance.fetchAggregateConversionInfo(for: .installation) { info, error in
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
    #endif

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

            // Drop entries belonging to superseded install instances. Without this,
            // every reinstall leaves an orphaned value behind in UserDefaults.
            for existing in defaults.dictionaryRepresentation().keys
            where existing.hasPrefix(ODMService.ODM_INFO_KEY_PREFIX) && existing != key {
                defaults.removeObject(forKey: existing)
            }

            defaults.set(info, forKey: key)
        }
    }
}
