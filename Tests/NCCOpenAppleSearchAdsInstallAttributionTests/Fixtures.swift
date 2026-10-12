import Foundation
@testable import NCCOpenAppleSearchAdsInstallAttribution

typealias Attribution = NCCOpenAppleSearchAdsInstallAttribution
typealias FetchError = NCCOpenAppleSearchAdsInstallAttribution.AttributionPayloadFetchError

/// Response bodies modeled on Apple's documented attribution payloads
enum Fixtures {
    /// A tap-through install with the full set of fields Apple documents
    static let clickPayloadJSON = """
        {"attribution":true,"orgId":40669820,"campaignId":542370539,"conversionType":"Download",\
        "clickDate":"2020-04-08T17:17Z","claimType":"Click","adGroupId":542317095,"countryOrRegion":"US",\
        "keywordId":87675432,"adId":542317136,"supplyPlacement":"APPSTORE_SEARCH_RESULTS"}
        """

    /// A view-through install: no `clickDate` and no `keywordId`, but an `impressionDate`
    static let impressionPayloadJSON = """
        {"attribution":true,"orgId":40669820,"campaignId":542370539,"conversionType":"Redownload",\
        "impressionDate":"2025-01-15T09:30Z","claimType":"Impression","adGroupId":542317095,\
        "countryOrRegion":"GB","adId":542317136,"supplyPlacement":"APPSTORE_TODAY_TAB"}
        """

    /// A payload as saved by 1.1, before `claimType`, `impressionDate` and `supplyPlacement` existed
    static let legacyPayloadJSON = """
        {"attribution":true,"orgId":40669820,"campaignId":542370539,"conversionType":"Download",\
        "clickDate":"2020-04-08T17:17Z","adGroupId":542317095,"countryOrRegion":"US","keywordId":87675432}
        """

    /// The test payload Apple returns when developer mode is on
    static let mockPayloadJSON = """
        {"attribution":true,"orgId":1234567890,"campaignId":1234567890,"conversionType":"Download",\
        "clickDate":"2020-04-08T17:17Z","adGroupId":1234567890,"countryOrRegion":"US",\
        "keywordId":12323222,"adId":1234567890}
        """

    static let notAttributedJSON = #"{"attribution":false}"#

    /// A token unique to one test, so parallel tests never share stubbed replies
    static func makeUniqueToken() -> String {
        "token-\(UUID().uuidString)"
    }

    /// A `UserDefaults` suite unique to one test
    static func makeIsolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "NCCOpenAppleSearchAdsInstallAttributionTests-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw FixtureError.cannotCreateUserDefaultsSuite(suiteName)
        }
        return userDefaults
    }

    /// Retries quickly so tests don't wait 5 seconds per attempt
    static let fastRetryPolicy = Attribution.NotFoundRetryPolicy(maximumAttempts: 3, delay: .milliseconds(10))
}

enum FixtureError: Error {
    case cannotCreateUserDefaultsSuite(String)
    case tokenUnavailable
}
