import XCTest
@testable import LinkrunnerKit

/// Covers the Test mode build facts (LIN-3369 / LIN-3425): the StoreKit environment
/// mapping, the local fallback, and provisioning profile parsing.
///
/// The invariant these tests protect: the SDK never reports `"production"` unless
/// StoreKit said so, and a missing or malformed profile never crashes or reads as debuggable.
final class BuildFactsTests: XCTestCase {

    // MARK: - Environment mapping

    func testMapsAppStoreEnvironmentRawValues() {
        XCTAssertEqual(BuildFacts.mapAppStoreEnvironment("Production"), "production")
        XCTAssertEqual(BuildFacts.mapAppStoreEnvironment("Sandbox"), "sandbox")
        XCTAssertEqual(BuildFacts.mapAppStoreEnvironment("Xcode"), "xcode")
        XCTAssertEqual(BuildFacts.mapAppStoreEnvironment(" xcode "), "xcode")
    }

    func testUnknownOrEmptyEnvironmentMapsToNil() {
        XCTAssertNil(BuildFacts.mapAppStoreEnvironment(nil))
        XCTAssertNil(BuildFacts.mapAppStoreEnvironment(""))
        XCTAssertNil(BuildFacts.mapAppStoreEnvironment("Staging"))
    }

    // MARK: - Fallback

    func testFallbackPrefersProvisioningProfileOverSandboxReceipt() {
        // Xcode-installed development builds also use a sandboxReceipt path.
        XCTAssertEqual(
            BuildFacts.fallbackEnvironment(hasProvisioningProfile: true, receiptFileName: "sandboxReceipt"),
            "development"
        )
    }

    func testFallbackSandboxReceiptWithoutProfileIsSandbox() {
        XCTAssertEqual(
            BuildFacts.fallbackEnvironment(hasProvisioningProfile: false, receiptFileName: "sandboxReceipt"),
            "sandbox"
        )
    }

    func testFallbackNeverGuessesProduction() {
        XCTAssertEqual(BuildFacts.fallbackEnvironment(hasProvisioningProfile: false, receiptFileName: "receipt"), "")
        XCTAssertEqual(BuildFacts.fallbackEnvironment(hasProvisioningProfile: false, receiptFileName: nil), "")
    }

    // MARK: - Combining

    private func local(
        profile: Bool = false,
        getTaskAllow: Bool? = nil,
        receipt: String? = nil,
        simulator: Bool = false
    ) -> LocalBuildFacts {
        LocalBuildFacts(
            hasProvisioningProfile: profile,
            getTaskAllow: getTaskAllow,
            receiptFileName: receipt,
            isSimulator: simulator
        )
    }

    func testStoreInstallIsProductionAndNotDebuggable() {
        let facts = BuildFacts.make(local: local(receipt: "receipt"), appTransactionEnvironment: "Production")
        XCTAssertEqual(facts.appStoreEnvironment, "production")
        XCTAssertFalse(facts.isDebuggable)
    }

    func testXcodeEnvironmentIsDebuggable() {
        let facts = BuildFacts.make(local: local(simulator: true), appTransactionEnvironment: "Xcode")
        XCTAssertEqual(facts.appStoreEnvironment, "xcode")
        XCTAssertTrue(facts.isDebuggable)
        XCTAssertTrue(facts.isEmulator)
    }

    func testDevelopmentSignedBuildOnIOS15IsDebuggable() {
        let facts = BuildFacts.make(
            local: local(profile: true, getTaskAllow: true, receipt: "sandboxReceipt"),
            appTransactionEnvironment: nil
        )
        XCTAssertEqual(facts.appStoreEnvironment, "development")
        XCTAssertTrue(facts.isDebuggable)
    }

    func testAdHocBuildIsNotDebuggable() {
        let facts = BuildFacts.make(local: local(profile: true, getTaskAllow: false), appTransactionEnvironment: nil)
        XCTAssertEqual(facts.appStoreEnvironment, "development")
        XCTAssertFalse(facts.isDebuggable)
    }

    func testTestFlightIsSandboxAndNotDebuggable() {
        let facts = BuildFacts.make(local: local(receipt: "sandboxReceipt"), appTransactionEnvironment: "Sandbox")
        XCTAssertEqual(facts.appStoreEnvironment, "sandbox")
        XCTAssertFalse(facts.isDebuggable)
    }

    func testDictionaryCarriesEveryContractKey() {
        let dict = BuildFacts.make(local: local(), appTransactionEnvironment: nil).toDictionary()
        XCTAssertEqual(dict["build_facts_version"] as? Int, 1)
        XCTAssertEqual(dict["is_debuggable"] as? Bool, false)
        XCTAssertEqual(dict["installer_package"] as? String, "")
        XCTAssertEqual(dict["app_store_environment"] as? String, "")
        XCTAssertEqual(dict["is_emulator"] as? Bool, false)
        XCTAssertEqual(Set(dict.keys), [
            "build_facts_version", "is_debuggable", "installer_package", "app_store_environment", "is_emulator"
        ])
    }

    func testLogLine() {
        let facts = BuildFacts.make(local: local(simulator: true), appTransactionEnvironment: "Xcode")
        XCTAssertEqual(
            facts.logLine,
            "Linkrunner build facts: debuggable=true, installer=(n/a on iOS), environment=xcode, simulator=true"
        )
    }

    // MARK: - Provisioning profile parsing

    /// A provisioning profile is a CMS blob around an XML plist; binary noise on both
    /// sides stands in for the DER envelope and signature.
    private func profile(getTaskAllow: String?) -> Data {
        let entitlement = getTaskAllow.map { "<key>get-task-allow</key><\($0)/>" } ?? ""
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>Example Dev Profile</string>
            <key>Entitlements</key>
            <dict>
                <key>application-identifier</key><string>ABCDE12345.com.example.app</string>
                \(entitlement)
            </dict>
        </dict>
        </plist>
        """
        var data = Data([0x30, 0x82, 0x2F, 0x00, 0x06, 0x09, 0x2A, 0x86, 0x48])
        data.append(xml.data(using: .utf8)!)
        data.append(Data([0xA0, 0x82, 0x0B, 0x00, 0xFF, 0x00]))
        return data
    }

    func testGetTaskAllowTrue() {
        XCTAssertEqual(BuildFacts.getTaskAllow(fromProvisioningProfile: profile(getTaskAllow: "true")), true)
    }

    func testGetTaskAllowFalse() {
        XCTAssertEqual(BuildFacts.getTaskAllow(fromProvisioningProfile: profile(getTaskAllow: "false")), false)
    }

    func testMissingGetTaskAllowIsNil() {
        XCTAssertNil(BuildFacts.getTaskAllow(fromProvisioningProfile: profile(getTaskAllow: nil)))
    }

    func testGarbageProfileIsNilAndDoesNotCrash() {
        XCTAssertNil(BuildFacts.getTaskAllow(fromProvisioningProfile: Data()))
        XCTAssertNil(BuildFacts.getTaskAllow(fromProvisioningProfile: Data([0x00, 0x01, 0x02])))
        XCTAssertNil(BuildFacts.getTaskAllow(fromProvisioningProfile: "<?xml <plist </plist>".data(using: .utf8)!))
        XCTAssertNil(BuildFacts.getTaskAllow(fromProvisioningProfile: "</plist> then <?xml".data(using: .utf8)!))
    }
}
