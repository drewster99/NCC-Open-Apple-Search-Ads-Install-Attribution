//
//  AttributionPayload+asAnalyticsDictionary.swift
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
extension NCCOpenAppleSearchAdsInstallAttribution.AttributionPayload {
    /// The `AttributionPayload` expressed as a (convenience) dictionary
    public var asAnalyticsDictionary: [String: Any?] {
        var dict: [String: Any?] = [
            "ASAOrgId": orgId,
            "ASACampaignID": campaignId,
            "ASAConversionType": conversionType,
            "ASAAdGroupID": adGroupId,
            "ASACountryOrRegion": countryOrRegion,
        ]

        if let keywordId {
            dict["ASAKeywordID"] = keywordId
        }
        if let adId {
            dict["ASAAdID"] = adId
        }
        if let clickDate {
            dict["ASAClickDate"] = clickDate
        }

        return dict
    }
}
