//
//  AttributionPayload.swift
//  Copyright (C) 2024 Nuclear Cyborg Corp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//                        limitations under the License.
//
//  Created by Andrew Benson on 7/17/24.
//


import Foundation

public extension NCCOpenAppleSearchAdsInstallAttribution {
    /// An Apple Search Ads install attribution payload
    struct AttributionPayload: Codable, Equatable, Sendable {
        /// Creates a payload from its fields, without the fields added in 1.2; normally payloads come from Apple's API instead
        public init(attribution: Bool, orgId: Int, campaignId: Int, conversionType: String, clickDate: String? = nil, adGroupId: Int, countryOrRegion: String, keywordId: Int? = nil, adId: Int? = nil) {
            self.init(attribution: attribution, orgId: orgId, campaignId: campaignId, conversionType: conversionType, clickDate: clickDate, adGroupId: adGroupId, countryOrRegion: countryOrRegion, keywordId: keywordId, adId: adId, claimType: nil, impressionDate: nil, supplyPlacement: nil)
        }

        /// Creates a payload from all of its fields; normally payloads come from Apple's API instead.
        /// The newer fields have no defaults so calls written for the older initializer stay unambiguous.
        public init(attribution: Bool, orgId: Int, campaignId: Int, conversionType: String, clickDate: String?, adGroupId: Int, countryOrRegion: String, keywordId: Int?, adId: Int?, claimType: ClaimType?, impressionDate: String?, supplyPlacement: SupplyPlacement?) {
            self.attribution = attribution
            self.orgId = orgId
            self.campaignId = campaignId
            self.conversionType = conversionType
            self.clickDate = clickDate
            self.adGroupId = adGroupId
            self.countryOrRegion = countryOrRegion
            self.keywordId = keywordId
            self.adId = adId
            self.claimType = claimType
            self.impressionDate = impressionDate
            self.supplyPlacement = supplyPlacement
        }

        /// Decodes a payload from Apple's JSON response body. Throws a `DecodingError` if `data` isn't a valid
        /// payload; never returns `nil`.
        public init?(_ data: Data) throws {
            self = try JSONDecoder().decode(AttributionPayload.self, from: data)
        }

        /// The attribution value.  `true` if the user tapped an Apple Search Ads ad up to 30 days before
        /// downloading your app, or viewed one up to 24 hours before (see `claimType`).
        /// If the API can't find a matching attribution record, the `attribution` value is `false`.
        public let attribution: Bool

        /// The identifier of the organization that owns the campaign.  Your `orgId` is the same as your account in the Apple
        /// Search Ads UI.  Obtain your `orgId` by calling "Get User ACL" in the Apple Search Ads Campaign Management API.
        public let orgId: Int

        /// The unique identifier for the campaign
        public let campaignId: Int

        /// The type of conversion: `Download`, `Redownload` or `PreOrder`.  Conversion types appear in your campaign
        /// reports in the Apple Search Ads Campaign Management API.  See the "ExtendedSpendRow" object for more
        /// information.
        public let conversionType: String

        /// The date and time when the user tapped an ad in a corresponding campaign.  Present only for tap-through
        /// attributions (`claimType` is `.click`).
        public let clickDate: String?

        /// The identifier for the ad group.  Use "Get Ad Group-Level Reports" to correlate your attribution response by
        /// `adGroupId` and its corresponding campaign in the Apple Search Ads Campaign Management API.
        public let adGroupId: Int

        /// The country or region for the campaign.  Use "Get Campaign-Level Reports" to correlate your attribution
        /// response by `countryOrRegion` in the Apple Search Ads Campaign Management API.
        public let countryOrRegion: String

        /// The identifier for the keyword.  Use "Get Keyword-Level Reports" in the Apple Search Ads Campaign
        /// Management API to correlate your attribution response by `keywordId`.
        /// Note, when you enable search match, the API doesn't return `keywordId` in the
        /// attribution response.
        public let keywordId: Int?

        /// The identifier representing the assignment relationship between an ad object and an ad group.
        /// Use "Get Ad-Level Reports" to correlate your attribution response by `adId` in the Apple Search Ads
        /// Campaign Management API.
        /// Note, `adId` doesn't return in the attribution payload if Custom Product Pages aren't associated
        /// with this campaign.  In campaigns using a Supply Source of `APPSTORE_TODAY_TAB` or
        /// `APPSTORE_SEARCH_RESULTS`, `adId` returns in the response.
        public let adId: Int?

        /// Whether the install was attributed to a tap (`.click`) or a view (`.impression`) of an ad.
        /// `nil` in payloads saved before this field was added.
        public let claimType: ClaimType?

        /// The date and time when the user viewed an ad in a corresponding campaign.  Present only for view-through
        /// attributions (`claimType` is `.impression`).
        public let impressionDate: String?

        /// Where in the App Store the ad appeared.  `nil` if Apple omits it, and in payloads saved before this field
        /// was added.
        public let supplyPlacement: SupplyPlacement?

        /// Returns `true` if `self` appears to be mock / test data
        public var isMockData: Bool {
            let mockValue: Int = 1234567890
            guard orgId != mockValue, campaignId != mockValue, adGroupId != mockValue, adId != mockValue else {
                return true
            }

            return false
        }
    }
}

public extension NCCOpenAppleSearchAdsInstallAttribution.AttributionPayload {
    /// How the user interacted with the ad that the install is attributed to.
    ///
    /// A struct rather than an enum so values Apple adds later are kept rather than failing to decode.
    struct ClaimType: RawRepresentable, Codable, Hashable, Sendable {
        /// Apple's string for the claim type
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// The user tapped the ad (tap-through attribution)
        public static let click = ClaimType(rawValue: "Click")

        /// The user viewed the ad (view-through attribution)
        public static let impression = ClaimType(rawValue: "Impression")
    }

    /// Where in the App Store an ad appeared.
    ///
    /// A struct rather than an enum so placements Apple adds later are kept rather than failing to decode.
    struct SupplyPlacement: RawRepresentable, Codable, Hashable, Sendable {
        /// Apple's string for the placement
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Search results
        public static let appStoreSearchResults = SupplyPlacement(rawValue: "APPSTORE_SEARCH_RESULTS")

        /// The Search tab
        public static let appStoreSearchTab = SupplyPlacement(rawValue: "APPSTORE_SEARCH_TAB")

        /// The Today tab
        public static let appStoreTodayTab = SupplyPlacement(rawValue: "APPSTORE_TODAY_TAB")

        /// Product pages, at the top of the "You Might Also Like" list
        public static let appStoreProductPages = SupplyPlacement(rawValue: "APPSTORE_PRODUCT_PAGES")
    }
}
