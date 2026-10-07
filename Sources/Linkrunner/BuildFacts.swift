import Foundation

#if canImport(StoreKit)
import StoreKit
#endif

/// Build facts sent inside `device_data` so the server can decide whether an install is
/// live or test (Test mode, LIN-3369).
///
/// Every value comes from the OS or the app's signing, never from a flag the developer
/// sets, so an App Store install can never be routed to test by mistake.
///
/// Keys (contract version `BuildFacts.VERSION`):
///
/// | key                     | type   | iOS value |
/// |-------------------------|--------|-----------|
/// | `build_facts_version`   | Int    | always `1`; its presence tells the server this SDK sends build facts |
/// | `is_debuggable`         | Bool   | `true` when the app is development-signed (`get-task-allow` in the embedded provisioning profile) or StoreKit reports the `xcode` environment |
/// | `installer_package`     | String | always `""` (Android only) |
/// | `app_store_environment` | String | see the mapping below |
/// | `is_emulator`           | Bool   | `true` on the iOS Simulator; informational only |
///
/// `app_store_environment` mapping:
///
/// 1. iOS 16+: `AppTransaction.shared.environment`, lowercased:
///    `Production` -> `"production"`, `Sandbox` (TestFlight) -> `"sandbox"`, `Xcode` -> `"xcode"`.
///    Waited for at most `BuildFactsProvider.ENVIRONMENT_TIMEOUT` and cached for the process.
/// 2. Otherwise (iOS 15, StoreKit error, timeout or an unknown value) a local fallback:
///    - an `embedded.mobileprovision` is present -> `"development"` (development, ad hoc or
///      enterprise signing; App Store and TestFlight builds never carry one)
///    - else the receipt file is named `sandboxReceipt` -> `"sandbox"` (TestFlight)
///    - else `""` (unknown). The SDK never guesses `"production"`: only StoreKit can say that.
///
/// The provisioning profile check runs before the receipt check because Xcode-installed
/// development builds also use a `sandboxReceipt` path, and they must not look like TestFlight.
struct BuildFacts: Sendable, Equatable {
    static let VERSION = 1

    static let KEY_VERSION = "build_facts_version"
    static let KEY_IS_DEBUGGABLE = "is_debuggable"
    static let KEY_INSTALLER_PACKAGE = "installer_package"
    static let KEY_APP_STORE_ENVIRONMENT = "app_store_environment"
    static let KEY_IS_EMULATOR = "is_emulator"

    static let ENVIRONMENT_PRODUCTION = "production"
    static let ENVIRONMENT_SANDBOX = "sandbox"
    static let ENVIRONMENT_XCODE = "xcode"
    static let ENVIRONMENT_DEVELOPMENT = "development"

    let isDebuggable: Bool
    let installerPackage: String
    let appStoreEnvironment: String
    let isEmulator: Bool

    func toDictionary() -> [String: Any] {
        return [
            BuildFacts.KEY_VERSION: BuildFacts.VERSION,
            BuildFacts.KEY_IS_DEBUGGABLE: isDebuggable,
            BuildFacts.KEY_INSTALLER_PACKAGE: installerPackage,
            BuildFacts.KEY_APP_STORE_ENVIRONMENT: appStoreEnvironment,
            BuildFacts.KEY_IS_EMULATOR: isEmulator
        ]
    }

    /// One line developers can read in the console to see what the server will use.
    var logLine: String {
        let environment = appStoreEnvironment.isEmpty ? "(unknown)" : appStoreEnvironment
        return "Linkrunner build facts: debuggable=\(isDebuggable), installer=(n/a on iOS), "
            + "environment=\(environment), simulator=\(isEmulator)"
    }

    // MARK: - Pure helpers (unit tested)

    /// Maps `AppStore.Environment.rawValue` to the wire value. Unknown or empty input
    /// returns nil so the caller falls back to local signals instead of guessing.
    static func mapAppStoreEnvironment(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else {
            return nil
        }
        switch value {
        case ENVIRONMENT_PRODUCTION: return ENVIRONMENT_PRODUCTION
        case ENVIRONMENT_SANDBOX: return ENVIRONMENT_SANDBOX
        case ENVIRONMENT_XCODE: return ENVIRONMENT_XCODE
        default: return nil
        }
    }

    /// Environment from local signals when StoreKit cannot answer. Never returns "production".
    static func fallbackEnvironment(hasProvisioningProfile: Bool, receiptFileName: String?) -> String {
        if hasProvisioningProfile {
            return ENVIRONMENT_DEVELOPMENT
        }
        if receiptFileName == "sandboxReceipt" {
            return ENVIRONMENT_SANDBOX
        }
        return ""
    }

    /// Combines local signals with the StoreKit environment (nil when unavailable).
    static func make(local: LocalBuildFacts, appTransactionEnvironment: String?) -> BuildFacts {
        let environment = mapAppStoreEnvironment(appTransactionEnvironment)
            ?? fallbackEnvironment(
                hasProvisioningProfile: local.hasProvisioningProfile,
                receiptFileName: local.receiptFileName
            )
        let debuggable = local.getTaskAllow == true || environment == ENVIRONMENT_XCODE
        return BuildFacts(
            isDebuggable: debuggable,
            installerPackage: "",
            appStoreEnvironment: environment,
            isEmulator: local.isSimulator
        )
    }

    /// Upper bound on the provisioning profile we are willing to read. Real profiles are
    /// tens of kilobytes; anything far larger is not something we should parse.
    static let MAX_PROFILE_BYTES = 2 * 1024 * 1024

    /// Extracts the XML property list embedded in a provisioning profile.
    ///
    /// The file is a CMS (PKCS#7) signed blob whose content is a plain XML plist, so the
    /// plist bytes can be located between `<?xml` (or `<plist`) and `</plist>` without a
    /// CMS parser. The signature is not verified: the result is only a hint for the server,
    /// and a tampered profile cannot make a store install look like a test install because
    /// the server checks the store environment first.
    static func provisioningProfilePlist(from data: Data) -> [String: Any]? {
        guard !data.isEmpty, data.count <= MAX_PROFILE_BYTES else { return nil }
        guard let endMarker = "</plist>".data(using: .utf8),
              let xmlMarker = "<?xml".data(using: .utf8),
              let plistMarker = "<plist".data(using: .utf8)
        else {
            return nil
        }
        guard let start = data.range(of: xmlMarker)?.lowerBound ?? data.range(of: plistMarker)?.lowerBound,
              let end = data.range(of: endMarker, options: [], in: start..<data.endIndex)?.upperBound,
              start < end
        else {
            return nil
        }
        let plistData = data.subdata(in: start..<end)
        do {
            let object = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
            return object as? [String: Any]
        } catch {
            return nil
        }
    }

    /// `Entitlements.get-task-allow` from a provisioning profile, or nil when the profile
    /// cannot be parsed or does not declare it.
    static func getTaskAllow(fromProvisioningProfile data: Data) -> Bool? {
        guard let plist = provisioningProfilePlist(from: data),
              let entitlements = plist["Entitlements"] as? [String: Any]
        else {
            return nil
        }
        if let value = entitlements["get-task-allow"] as? Bool {
            return value
        }
        if let value = entitlements["get-task-allow"] as? NSNumber {
            return value.boolValue
        }
        return nil
    }
}

/// Signals that can be read synchronously from the app bundle and the build.
struct LocalBuildFacts: Sendable, Equatable {
    let hasProvisioningProfile: Bool
    /// nil when there is no profile or it could not be parsed.
    let getTaskAllow: Bool?
    /// Last path component of the App Store receipt URL, e.g. "receipt" or "sandboxReceipt".
    let receiptFileName: String?
    let isSimulator: Bool

    /// Reads the local facts. Never throws and never crashes on a missing or odd file.
    static func read(bundle: Bundle = .main) -> LocalBuildFacts {
        var hasProfile = false
        var getTaskAllow: Bool? = nil
        if let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") {
            hasProfile = true
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                getTaskAllow = BuildFacts.getTaskAllow(fromProvisioningProfile: data)
            }
        }

        // appStoreReceiptURL is deprecated from iOS 18 but still returns the path, and
        // only the file name is read here (the receipt itself is not opened).
        let receiptFileName = bundle.appStoreReceiptURL?.lastPathComponent

        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        return LocalBuildFacts(
            hasProvisioningProfile: hasProfile,
            getTaskAllow: getTaskAllow,
            receiptFileName: receiptFileName,
            isSimulator: isSimulator
        )
    }
}

/// Resolves build facts once per process.
///
/// The StoreKit lookup is started early (`prewarm()`, called at the top of `initialize`)
/// so it overlaps other init work. Callers wait for it only until
/// `ENVIRONMENT_TIMEOUT` after the lookup started; after that they get the local fallback
/// immediately, and the late StoreKit answer is cached for later requests.
@available(iOS 15.0, *)
actor BuildFactsProvider {
    static let shared = BuildFactsProvider()

    /// How long any caller may wait for `AppTransaction.shared`, measured from when the
    /// lookup started. Short on purpose: init must not stall on StoreKit.
    static let ENVIRONMENT_TIMEOUT: TimeInterval = 1.5

    private enum EnvironmentState {
        case notStarted
        case pending(task: Task<String?, Never>, startedAt: Date)
        case resolved(String?)
    }

    private enum WaitOutcome: Sendable {
        case value(String?)
        case timedOut
    }

    private var environmentState: EnvironmentState = .notStarted
    private var cachedLocal: LocalBuildFacts?
    private var hasLogged = false

    init() {}

    /// Starts the StoreKit lookup without waiting for it.
    func prewarm() {
        startEnvironmentLookupIfNeeded()
    }

    /// Current build facts. Waits for StoreKit at most until the shared deadline.
    func facts() async -> BuildFacts {
        let local = localFacts()
        let environment = await appTransactionEnvironment()
        return BuildFacts.make(local: local, appTransactionEnvironment: environment)
    }

    /// True the first time it is called in the process, so the facts are logged once.
    func shouldLog() -> Bool {
        if hasLogged { return false }
        hasLogged = true
        return true
    }

    // MARK: - Private

    private func localFacts() -> LocalBuildFacts {
        if let cachedLocal = cachedLocal { return cachedLocal }
        let local = LocalBuildFacts.read()
        cachedLocal = local
        return local
    }

    private func setResolvedEnvironment(_ value: String?) {
        environmentState = .resolved(value)
    }

    private func startEnvironmentLookupIfNeeded() {
        guard case .notStarted = environmentState else { return }
        let task = Task<String?, Never> {
            let value = await BuildFactsProvider.fetchAppTransactionEnvironment()
            // Task inherits the actor's isolation here, so this is a synchronous call.
            self.setResolvedEnvironment(value)
            return value
        }
        environmentState = .pending(task: task, startedAt: Date())
    }

    private func appTransactionEnvironment() async -> String? {
        startEnvironmentLookupIfNeeded()
        switch environmentState {
        case .resolved(let value):
            return value
        case .notStarted:
            return nil
        case .pending(let task, let startedAt):
            let remaining = BuildFactsProvider.ENVIRONMENT_TIMEOUT - Date().timeIntervalSince(startedAt)
            guard remaining > 0 else { return nil }
            switch await BuildFactsProvider.wait(for: task, seconds: remaining) {
            case .value(let value): return value
            case .timedOut: return nil
            }
        }
    }

    /// Races the lookup against a sleep. The lookup task is unstructured, so cancelling
    /// the group does not cancel it: a late answer still lands in the cache.
    private static func wait(for task: Task<String?, Never>, seconds: TimeInterval) async -> WaitOutcome {
        await withTaskGroup(of: WaitOutcome.self) { group in
            group.addTask { .value(await task.value) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    /// `AppTransaction.shared.environment` mapped to the wire value, or nil when it is
    /// unavailable (below iOS 16, StoreKit error, or an unknown value).
    private static func fetchAppTransactionEnvironment() async -> String? {
        #if canImport(StoreKit)
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            do {
                let result = try await AppTransaction.shared
                // The environment is a hint for the server, not an entitlement, so an
                // unverified transaction's payload is still used.
                let transaction: AppTransaction
                switch result {
                case .verified(let value):
                    transaction = value
                case .unverified(let value, _):
                    transaction = value
                }
                return BuildFacts.mapAppStoreEnvironment(transaction.environment.rawValue)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
