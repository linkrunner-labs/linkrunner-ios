import Foundation

/// Reads the Meta (Facebook) SDK's anonymous ID when the host app bundles the Meta SDK, so
/// the backend can forward it to Meta as `anon_id` on app event postbacks.
///
/// LinkrunnerKit declares no dependency on the Meta SDK. Both lookups resolve at runtime and
/// return `nil` when the Meta SDK is absent or has not stored an ID yet.
///
/// Rules this reader keeps:
///  - Read only. It never starts or configures the Meta SDK and never writes to its storage.
///    `FBSDKBasicUtility.anonymousID` and anything on `FBSDKAppEvents` are deliberately left
///    alone: the former creates and persists an ID, and touching the latter runs Meta's class
///    set-up, whose methods throw an Objective-C exception in debug builds when the Meta SDK
///    has not started. Swift cannot catch that, so the app would crash.
///  - No dependency on start-up order. A miss is never cached, so the ID is picked up on the
///    first request made after the Meta SDK has it.
///  - Never slow or break a Linkrunner call: every failure degrades to `nil`.
///  - Never log the value.
enum MetaAnonymousIdReader {

    /// Build-time opt-out, read from the host app's `Info.plist`. Absent means on.
    private static let plistFlagKey = "LinkrunnerMetaAnonymousIdCollectionEnabled"

    /// Meta's own persistence file and key (facebook-ios-sdk `FBSDKBasicUtility`).
    private static let anonymousIdFileName = "com-facebook-sdk-PersistedAnonymousID.json"
    private static let anonymousIdKey = "anon_id"

    private static let basicUtilityClassName = "FBSDKBasicUtility"
    private static let retrieveSelectorName = "retrievePersistedAnonymousID"

    /// Set only once a real value is found. A miss is never cached.
    @Synchronized private static var cachedId: String?

    /// Directory holding Meta's persisted ID file. Overridden by tests only; production
    /// always resolves the app's own Library directory.
    @Synchronized internal static var persistedFileDirectoryOverride: URL?

    /// The Meta anonymous ID, or `nil` when it is not available.
    static func read() -> String? {
        if let cached = cachedId {
            return cached
        }

        guard isCollectionEnabled() else { return nil }

        // Meta's own reader first, so we follow it if it ever moves the file. The direct read
        // is the fallback for builds where the class or selector is not reachable.
        guard let id = readViaMetaSdk() ?? readPersistedFile() else { return nil }

        cachedId = id
        return id
    }

    /// Clears the process cache and any test override. Test seam only.
    static func resetForTesting() {
        cachedId = nil
        persistedFileDirectoryOverride = nil
    }

    private static func isCollectionEnabled() -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: plistFlagKey) else {
            return true
        }

        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return (text as NSString).boolValue }
        return true
    }

    /// Asks `FBSDKBasicUtility` for the stored ID. This only reads: unlike `anonymousID`, it
    /// creates nothing when no ID has been persisted yet.
    private static func readViaMetaSdk() -> String? {
        guard let utilityClass = NSClassFromString(basicUtilityClassName) as? NSObject.Type else {
            return nil
        }

        let selector = NSSelectorFromString(retrieveSelectorName)
        guard utilityClass.responds(to: selector) else { return nil }
        guard let result = utilityClass.perform(selector) else { return nil }

        return (result.takeUnretainedValue() as? String)?.nonBlank
    }

    /// Reads the file `FBSDKBasicUtility` persists the ID to, under the app's Library directory.
    private static func readPersistedFile() -> String? {
        guard let library = persistedFileDirectoryOverride ?? FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let fileUrl = library.appendingPathComponent(anonymousIdFileName)

        guard let data = try? Data(contentsOf: fileUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json[anonymousIdKey] as? String else { return nil }

        return id.nonBlank
    }
}

private extension String {
    /// `nil` for an empty or whitespace-only value, so a blank never reaches the wire.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
