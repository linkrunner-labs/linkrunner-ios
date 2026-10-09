import XCTest
@testable import LinkrunnerKit

final class AttributionDataResponseTests: XCTestCase {

    private func parse(_ json: String) throws -> LRAttributionDataResponse {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try LRAttributionDataResponse(dictionary: XCTUnwrap(object as? SendableDictionary))
    }

    func testParsesIdfaAndLeavesGaidNil() throws {
        let response = try parse(#"{"deeplink":null,"campaign_data":null,"attribution_source":"ORGANIC","gaid":null,"idfa":"6D92078A-8246-4BA4-AE5B-76104861E7DC"}"#)

        XCTAssertEqual(response.idfa, "6D92078A-8246-4BA4-AE5B-76104861E7DC")
        XCTAssertNil(response.gaid)
        XCTAssertEqual(response.toDictionary()["idfa"] as? String, "6D92078A-8246-4BA4-AE5B-76104861E7DC")
        XCTAssertNil(response.toDictionary()["gaid"])
    }

    func testParsesNullIdfa() throws {
        let response = try parse(#"{"deeplink":null,"campaign_data":null,"attribution_source":"ORGANIC","gaid":null,"idfa":null}"#)

        XCTAssertNil(response.gaid)
        XCTAssertNil(response.idfa)
    }

    func testParsesResponseWithoutGaidAndIdfa() throws {
        let response = try parse(#"{"deeplink":"https://example.com/path","campaign_data":null,"attribution_source":"ORGANIC"}"#)

        XCTAssertEqual(response.deeplink, "https://example.com/path")
        XCTAssertNil(response.gaid)
        XCTAssertNil(response.idfa)
    }

    func testDecodesGaidAndIdfaWithCodable() throws {
        let json = #"{"attribution_source":"META","gaid":null,"idfa":"6D92078A-8246-4BA4-AE5B-76104861E7DC"}"#
        let response = try JSONDecoder().decode(LRAttributionDataResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.idfa, "6D92078A-8246-4BA4-AE5B-76104861E7DC")
        XCTAssertNil(response.gaid)
    }
}
