# NCCOpenAppleSearchAdsInstallAttribution

Install attribution for apps downloaded through Apple Search Ads (Apple Ads), using Apple's
[AdServices](https://developer.apple.com/documentation/adservices) framework and attribution API.

On launch it fetches the attribution record for this install, saves it, and hands it to your closures:
once every launch with the saved payload (for user properties), and once ever when a new payload
arrives (for an "attribution received" analytics event). The payload and any error are also
`@Published` for SwiftUI.

- Retries Apple's "not available yet" 404 as Apple recommends: 3 attempts, 5 seconds apart.
- Recognizes Apple's developer-mode test payload and reports it as an error instead of a real attribution.
- No dependencies. No App Tracking Transparency prompt is needed: AdServices doesn't require it.

## Requirements

- iOS 17+ or macOS 14+
- Swift 6.1+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/drewster99/NCC-Open-Apple-Search-Ads-Install-Attribution.git", from: "1.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "NCCOpenAppleSearchAdsInstallAttribution", package: "NCC-Open-Apple-Search-Ads-Install-Attribution"),
    ]),
]
```

## Usage

Create one instance at app launch and keep it alive. Work starts as soon as it's created.

```swift
import SwiftUI
import NCCOpenAppleSearchAdsInstallAttribution

@main
struct MyApp: App {
    @StateObject private var adAttribution = NCCOpenAppleSearchAdsInstallAttribution(
        { payload in
            // Every launch once a payload is known, including one loaded from a previous launch
            Analytics.setUserProperty(payload.conversionType, forName: "ASAConversionType")
        },
        onNewAttributionPayloadReceived: { payload in
            // Only when a payload arrives that differs from the saved one
            Analytics.logEvent("asa_attribution_received", parameters: payload.asAnalyticsDictionary)
        }
    )

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`adAttribution.attributionPayload` and `adAttribution.error` are `@Published`. `error` is set when the
token or the attribution record can't be fetched, including `AttributionPayloadFetchError.mockDataReceived`
when Apple returns its developer-mode test payload.

## The payload

| Property | Notes |
|---|---|
| `attribution` | `true` for a tap within 30 days or a view within 24 hours before download |
| `orgId`, `campaignId`, `adGroupId` | Correlate with the Apple Ads Campaign Management API |
| `keywordId` | Absent for search match |
| `adId` | Absent when no custom product page is associated |
| `conversionType` | `Download`, `Redownload` or `PreOrder` |
| `claimType` | `.click` (tap-through) or `.impression` (view-through) |
| `clickDate` / `impressionDate` | Present for tap-through / view-through respectively |
| `countryOrRegion` | The campaign's country or region |
| `supplyPlacement` | Where the ad ran, e.g. `.appStoreSearchResults`, `.appStoreTodayTab` |

`claimType` and `supplyPlacement` keep values Apple adds later in `rawValue` rather than failing to decode.

`asAnalyticsDictionary` returns the payload as `ASA`-prefixed keys (`ASAOrgId`, `ASACampaignID`,
`ASAConversionType`, `ASAAdGroupID`, `ASACountryOrRegion`, and when present `ASAKeywordID`, `ASAAdID`,
`ASAClickDate`, `ASAImpressionDate`, `ASAClaimType`, `ASASupplyPlacement`).

## Testing

With developer mode on, Apple's API returns a test payload whose identifiers are `1234567890`. It is
detected (`isMockData`), not saved, and reported through `error`.

## License

Apache 2.0. See [LICENSE](LICENSE).
