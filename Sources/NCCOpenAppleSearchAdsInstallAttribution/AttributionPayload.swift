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
    struct AttributionPayload: Codable, Equatable {
        public init(attribution: Bool, orgId: Int, campaignId: Int, conversionType: String, clickDate: String? = nil, adGroupId: Int, countryOrRegion: String, keywordId: Int? = nil, adId: Int? = nil) {
            self.attribution = attribution
            self.orgId = orgId
            self.campaignId = campaignId
            self.conversionType = conversionType
            self.clickDate = clickDate
            self.adGroupId = adGroupId
            self.countryOrRegion = countryOrRegion
            self.keywordId = keywordId
            self.adId = adId
        }

        public init?(_ data: Data) throws {
            self = try JSONDecoder().decode(AttributionPayload.self, from: data)
        }
        /// The attribution value.  `true` if user clicks on Apple Search Ads impression up to 30 days before your app download.
        /// If the API can't find a matching attribution record, the `attribution` value is `false`.
        public let attribution: Bool

        /// The identifier of the organization that owns the campaign.  Your `orgId` is the same as your account in the Apple
        /// Search Ads UI.  Obtain your `orgId` by calling "Get User ACL" in the Apple Search Ads Campaign Management API.
        public let orgId: Int

        /// The unique identifier for the campaign
        public let campaignId: Int

        /// The type of conversion -- either `Download` or `Redownload`.  Conversion types appear in your campaign
        /// reports in the Apple Search Ads Campaign Management API.  See the "ExtendedfSpendRow" object for more
        /// information.
        public let conversionType: String

        /// The date and time when the user clicks an ad in a corresponding campagin.  This field only appears in the
        /// detailed attribution response payload.  The detailed payload is only returned if the app has requested
        /// permission to track using `ATTrackingManager` and the `ATTrackingManager.AuthorizationStatus`
        /// is `.authorized`.
        public let clickDate: String?

        /// The identifier for the ad group.  Use "Get Ad Group-Level Reports" to correlate your attribution response by
        /// `adGroupId` and its corresponding campaign in the Apple Search Ads Campaign Management API.
        public let adGroupId: Int

        /// The country or region for the campaign.  Use "Get Campaign-Level Reports" to correlate your attribution
        /// response by `countryOrRegion` in the Apple Search Ads Campaign Management API.
        public let countryOrRegion: String

        /// The identifier for the keyword.  Use "Get Keyword-Level Reports" int he Apple Search Ads Campaign
        /// Management API to correlate your attribution response by `keywordId`.
        /// Note, when you enable search match, the API doesn't return `keywordId` in the
        /// attribution response.
        public let keywordId: Int?

        /// The identifier respresenting the assignment relationship between an ad object and an ad group.
        /// Use "Get Ad-Level Reports" to correlate your attribution response by `adId` in the Apple Search Ads
        /// Campaign Management API.
        /// Note, `adId` doesn't return in the attribution payload if Custom Product Pages aren't associated
        /// with this campaign.  In campaigns using a Supply Source of `APPSTORE_TODAY_TAB` or
        /// `APPSTORE_SEARCH_RESULTS`, `adId` returns in the response.
        public let adId: Int?

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
