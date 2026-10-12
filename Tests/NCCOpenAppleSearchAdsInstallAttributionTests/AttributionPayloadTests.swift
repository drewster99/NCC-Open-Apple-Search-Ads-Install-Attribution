import Foundation
import Testing
@testable import NCCOpenAppleSearchAdsInstallAttribution

typealias Payload = NCCOpenAppleSearchAdsInstallAttribution.AttributionPayload

@Suite("AttributionPayload")
struct AttributionPayloadTests {

    private func decode(_ json: String) throws -> Payload {
        try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
    }

    @Test("Tap-through payload decodes claimType and supplyPlacement")
    func clickPayload() throws {
        let payload = try decode(Fixtures.clickPayloadJSON)
        #expect(payload.claimType == .click)
        #expect(payload.clickDate == "2020-04-08T17:17Z")
        #expect(payload.impressionDate == nil)
        #expect(payload.supplyPlacement == .appStoreSearchResults)
        #expect(!payload.isMockData)
    }

    @Test("View-through payload decodes impressionDate and has no clickDate or keywordId")
    func impressionPayload() throws {
        let payload = try decode(Fixtures.impressionPayloadJSON)
        #expect(payload.claimType == .impression)
        #expect(payload.impressionDate == "2025-01-15T09:30Z")
        #expect(payload.clickDate == nil)
        #expect(payload.keywordId == nil)
        #expect(payload.conversionType == "Redownload")
        #expect(payload.supplyPlacement == .appStoreTodayTab)
    }

    @Test("A payload saved by 1.1, without the newer fields, still decodes")
    func legacyPayload() throws {
        let payload = try decode(Fixtures.legacyPayloadJSON)
        #expect(payload.orgId == 40669820)
        #expect(payload.claimType == nil)
        #expect(payload.impressionDate == nil)
        #expect(payload.supplyPlacement == nil)
        #expect(payload.adId == nil)
    }

    @Test("Unknown claimType and supplyPlacement values are kept, not rejected")
    func unknownValuesKept() throws {
        let json = Fixtures.clickPayloadJSON
            .replacingOccurrences(of: #""claimType":"Click""#, with: #""claimType":"Glance""#)
            .replacingOccurrences(of: "APPSTORE_SEARCH_RESULTS", with: "APPSTORE_SOMEWHERE_NEW")
        let payload = try decode(json)
        #expect(payload.claimType?.rawValue == "Glance")
        #expect(payload.supplyPlacement?.rawValue == "APPSTORE_SOMEWHERE_NEW")
    }

    @Test("Placement constants match Apple's documented strings")
    func placementRawValues() {
        #expect(Payload.SupplyPlacement.appStoreSearchResults.rawValue == "APPSTORE_SEARCH_RESULTS")
        #expect(Payload.SupplyPlacement.appStoreSearchTab.rawValue == "APPSTORE_SEARCH_TAB")
        #expect(Payload.SupplyPlacement.appStoreTodayTab.rawValue == "APPSTORE_TODAY_TAB")
        #expect(Payload.SupplyPlacement.appStoreProductPages.rawValue == "APPSTORE_PRODUCT_PAGES")
        #expect(Payload.ClaimType.click.rawValue == "Click")
        #expect(Payload.ClaimType.impression.rawValue == "Impression")
    }

    @Test("Encoding then decoding preserves every field")
    func roundTrip() throws {
        let original = try decode(Fixtures.impressionPayloadJSON)
        let restored = try JSONDecoder().decode(Payload.self, from: JSONEncoder().encode(original))
        #expect(restored == original)
    }

    @Test("A payload missing a required field fails to decode")
    func missingRequiredField() {
        #expect(throws: DecodingError.self) { try decode(#"{"attribution":true,"orgId":1}"#) }
    }

    @Test("init(_ data:) decodes or throws")
    func dataInitializer() throws {
        let payload = try Payload(Data(Fixtures.clickPayloadJSON.utf8))
        #expect(payload?.orgId == 40669820)
        #expect(throws: DecodingError.self) { try Payload(Data("{}".utf8)) }
    }

    @Test("The 1.1 initializer leaves the newer fields nil; the full initializer sets them")
    func initializers() {
        let original = Payload(attribution: true, orgId: 1, campaignId: 2, conversionType: "Download",
                               adGroupId: 3, countryOrRegion: "US")
        #expect(original.claimType == nil)
        #expect(original.impressionDate == nil)
        #expect(original.supplyPlacement == nil)

        let full = Payload(attribution: true, orgId: 1, campaignId: 2, conversionType: "Download",
                           clickDate: nil, adGroupId: 3, countryOrRegion: "US", keywordId: nil, adId: 4,
                           claimType: .impression, impressionDate: "2025-01-15T09:30Z",
                           supplyPlacement: .appStoreTodayTab)
        #expect(full.claimType == .impression)
        #expect(full.impressionDate == "2025-01-15T09:30Z")
        #expect(full.supplyPlacement == .appStoreTodayTab)
        #expect(full.adId == 4)
    }

    @Test("Apple's developer-mode payload is detected as mock data")
    func mockDetected() throws {
        #expect(try decode(Fixtures.mockPayloadJSON).isMockData)
    }

    @Test("Any single mock identifier marks the payload as mock data")
    func mockDetectedPerField() {
        let mockValue = 1234567890
        func make(orgId: Int = 1, campaignId: Int = 2, adGroupId: Int = 3, adId: Int? = 4) -> Payload {
            Payload(attribution: true, orgId: orgId, campaignId: campaignId, conversionType: "Download",
                    adGroupId: adGroupId, countryOrRegion: "US", adId: adId)
        }
        #expect(!make().isMockData)
        #expect(!make(adId: nil).isMockData)
        #expect(make(orgId: mockValue).isMockData)
        #expect(make(campaignId: mockValue).isMockData)
        #expect(make(adGroupId: mockValue).isMockData)
        #expect(make(adId: mockValue).isMockData)
    }

    @Test("Analytics dictionary includes optional keys only when present")
    func analyticsDictionary() throws {
        let click = try decode(Fixtures.clickPayloadJSON).asAnalyticsDictionary
        #expect(click["ASAOrgId"] as? Int == 40669820)
        #expect(click["ASACampaignID"] as? Int == 542370539)
        #expect(click["ASAAdGroupID"] as? Int == 542317095)
        #expect(click["ASAConversionType"] as? String == "Download")
        #expect(click["ASACountryOrRegion"] as? String == "US")
        #expect(click["ASAKeywordID"] as? Int == 87675432)
        #expect(click["ASAAdID"] as? Int == 542317136)
        #expect(click["ASAClickDate"] as? String == "2020-04-08T17:17Z")
        #expect(click["ASAClaimType"] as? String == "Click")
        #expect(click["ASASupplyPlacement"] as? String == "APPSTORE_SEARCH_RESULTS")
        #expect(click["ASAImpressionDate"] == nil)

        let legacy = try decode(Fixtures.legacyPayloadJSON).asAnalyticsDictionary
        #expect(Set(legacy.keys) == ["ASAOrgId", "ASACampaignID", "ASAConversionType", "ASAAdGroupID",
                                     "ASACountryOrRegion", "ASAKeywordID", "ASAClickDate"])

        let impression = try decode(Fixtures.impressionPayloadJSON).asAnalyticsDictionary
        #expect(impression["ASAImpressionDate"] as? String == "2025-01-15T09:30Z")
        #expect(impression["ASAClaimType"] as? String == "Impression")
        #expect(impression["ASAClickDate"] == nil)
        #expect(impression["ASAKeywordID"] == nil)
    }
}
