import XCTest
@testable import LinkrunnerKit

/// Covers `MetaAnonymousIdReader` when the Meta SDK is **not** linked into the app (LIN-5027).
///
/// This is the path most apps take: LinkrunnerKit has no build-time dependency on
/// `FBSDKCoreKit`, so without it every entry point must degrade to `nil` rather than
/// crashing. The test bundle does not link the Meta SDK, so `NSClassFromString` returns nil
/// here and these exercise the real absent path, with the persisted-file read driven from a
/// temporary directory.
@available(iOS 15.0, *)
final class MetaAnonymousIdReaderTests: XCTestCase {

    private static let anonymousId = "XZ3f8a1c2d-0b44-4a7e-9f10-55c2a9e7b001"
    private static let fileName = "com-facebook-sdk-PersistedAnonymousID.json"

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        MetaAnonymousIdReader.resetForTesting()

        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-anon-id-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        MetaAnonymousIdReader.persistedFileDirectoryOverride = directory
    }

    override func tearDownWithError() throws {
        MetaAnonymousIdReader.resetForTesting()
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private func writeStoredFile(_ contents: String) throws {
        try contents.write(
            to: directory.appendingPathComponent(Self.fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func removeStoredFile() {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(Self.fileName))
    }

    func testMetaSDKIsGenuinelyAbsentInThisBundle() {
        // Guards the premise of every other test here. If FBSDKCoreKit ever gets linked into
        // the test target, these stop testing what they claim to.
        XCTAssertNil(NSClassFromString("FBSDKBasicUtility"),
                     "test bundle must not link FBSDKCoreKit")
    }

    func testReturnsNilWithoutTheMetaSDKAndWithoutAStoredFile() {
        XCTAssertNil(MetaAnonymousIdReader.read())
    }

    func testReadsTheIdMetaPersisted() throws {
        try writeStoredFile("{\"anon_id\":\"\(Self.anonymousId)\"}")

        XCTAssertEqual(MetaAnonymousIdReader.read(), Self.anonymousId)
    }

    func testTreatsABlankStoredValueAsAbsent() throws {
        try writeStoredFile("{\"anon_id\":\"   \"}")

        XCTAssertNil(MetaAnonymousIdReader.read())
    }

    func testAMalformedFileDegradesToNil() throws {
        try writeStoredFile("not json at all")

        XCTAssertNil(MetaAnonymousIdReader.read())
    }

    func testAFileWithoutTheKeyDegradesToNil() throws {
        try writeStoredFile("{\"something_else\":\"value\"}")

        XCTAssertNil(MetaAnonymousIdReader.read())
    }

    func testARealValueIsCachedForTheProcess() throws {
        try writeStoredFile("{\"anon_id\":\"\(Self.anonymousId)\"}")
        XCTAssertEqual(MetaAnonymousIdReader.read(), Self.anonymousId)

        // Meta's storage is gone, but the resolved value survives.
        removeStoredFile()
        XCTAssertEqual(MetaAnonymousIdReader.read(), Self.anonymousId)
    }

    func testAMissIsNeverCachedSoALateMetaSDKIsPickedUp() throws {
        XCTAssertNil(MetaAnonymousIdReader.read())

        // The Meta SDK started after our first request.
        try writeStoredFile("{\"anon_id\":\"\(Self.anonymousId)\"}")
        XCTAssertEqual(MetaAnonymousIdReader.read(), Self.anonymousId)
    }
}
