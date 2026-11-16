import XCTest

/// The manifest declares every required reason API the source uses and lists no tracking domains.
final class PrivacyManifestTests: XCTestCase {

    private static let sourcesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../Sources/Linkrunner")
        .standardizedFileURL

    /// Required reason API category -> source tokens that use it.
    private static let requiredReasonAPIs: [String: [String]] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["UserDefaults"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": [
            "creationDate", "modificationDate", ".fileModificationDate", "attributesOfItem", "getattrlist", "fstat(", "stat(",
        ],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["systemUptime", "mach_absolute_time"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["volumeAvailableCapacity", "systemFreeSize", "statfs"],
        "NSPrivacyAccessedAPICategoryActiveKeyboards": ["activeInputModes"],
    ]

    private func loadManifest() throws -> [String: Any] {
        let url = Self.sourcesDir.appendingPathComponent("PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    private func declaredAPICategories(_ manifest: [String: Any]) throws -> [String: [String]] {
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var result: [String: [String]] = [:]
        for entry in entries {
            let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
            result[category] = try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
        }
        return result
    }

    private func sourceText() throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: Self.sourcesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    func testTrackingIsDeclaredWithoutTrackingDomains() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, true)
        let domains = try XCTUnwrap(manifest["NSPrivacyTrackingDomains"] as? [String])
        XCTAssertTrue(domains.isEmpty, "Listed domains are blocked when ATT is denied")
    }

    func testUserDefaultsIsDeclaredWithAppOnlyReason() throws {
        let declared = try declaredAPICategories(loadManifest())
        XCTAssertEqual(declared["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
    }

    func testEveryRequiredReasonAPIUsedInSourceIsDeclared() throws {
        let declared = try declaredAPICategories(loadManifest())
        let source = try sourceText()
        for (category, tokens) in Self.requiredReasonAPIs {
            let used = tokens.filter { source.contains($0) }
            if !used.isEmpty {
                XCTAssertNotNil(declared[category], "\(category) used via \(used) but not declared")
            }
            if let reasons = declared[category] {
                XCTAssertFalse(reasons.isEmpty, "\(category) declared without a reason")
            }
        }
    }

    func testCollectedDataTypesAreComplete() throws {
        let entries = try XCTUnwrap(loadManifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = Set(entries.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        let expected: Set<String> = [
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeAdvertisingData",
            "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypePurchaseHistory",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypePhoneNumber",
            "NSPrivacyCollectedDataTypeName",
        ]
        XCTAssertEqual(types, expected)
        for entry in entries {
            XCTAssertNotNil(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool)
            XCTAssertNotNil(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool)
            let purposes = try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            XCTAssertFalse(purposes.isEmpty)
        }
    }
}
