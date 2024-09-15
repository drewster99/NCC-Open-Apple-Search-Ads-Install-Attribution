//
//  NCCOpenAppleSearchAdsInstallAttribution.swift
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
import SwiftUI
import AdServices
import OSLog


private let logger = Logger(subsystem: "NCCOpenAppleSearchAdsInstallAttribution", category: "NCCOpenAppleSearchAdsInstallAttribution")

/// Fetches advertising install attribution record for app instances that were installed with Apple Search Ads
public class NCCOpenAppleSearchAdsInstallAttribution: ObservableObject {

    /// An error in fetching ad attribution record
    public enum AttributionPayloadFetchError: String, Swift.Error, LocalizedError {

        /// Response was not an `HTTPURLResponse`
        case responseIsNotHTTPURLResponse = "Response is not an HTTPURLResponse"

        /// An unexpected HTTP status code was returned
        case unknownHTTPStatusCodeInResponse = "Received unexpected HTTP status code - response ignored"

        /// The attribution record returned appears to be mock data
        case mockDataReceived = "Attribution payload appears to be mock data"

        /// Token is invalid
        case status400InvalidToken = "Token is invalid"

        /// Tokens have TTL of 24 hours.   This error is returned if the API call exceeds 24 hours.
        /// If the token is valid, a best practice is to initiate retries at intervals of 5 seconds, with a
        /// maximum of 3 attempts.
        case status404NotFound = "No record found for token"

        /// Your request might be valid, but you'll need to retry it later
        case status500ServerUnavailable = "The Apple Search Ads server is temporarily down or unavailable"

        public var errorDescription: String? { rawValue }
    }

    /// Apple Search Ads app install attribution payload returned from Apple's server
    @Published public var attributionPayload: AttributionPayload?

    /// The most recent `Error`, if any, or `nil`, if no error has occurred
    @Published public var error: Swift.Error?

    private var savedAttributionPayloadUserDefaultsKey = "NCCOpenAppleSearchAdsInstallAttribution_savedAttributionPayload"
    private var savedAttributionPayload: AttributionPayload? {
        get {
            guard let data = UserDefaults.standard.data(forKey: savedAttributionPayloadUserDefaultsKey) else {
                return nil
            }
            do {
                let result = try JSONDecoder().decode(AttributionPayload.self, from: data)
                return result
            } catch {
                logger.error("Saved attribution payload could not be decoded: \(error)")
                return nil
            }
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: savedAttributionPayloadUserDefaultsKey)
                return
            }
            do {
                let data = try JSONEncoder().encode(newValue)
                UserDefaults.standard.setValue(data, forKey: savedAttributionPayloadUserDefaultsKey)
            } catch {
                logger.error("Unable to JSON encode savedAttributionPayload for saving: \(error)")
                return
            }
        }
    }

    /// Fetches the app's attribution token, returning it as a `String` or throwing if an error occurs
    private func getAttributionToken() async throws -> String {
        // Several forum posts (stackoverflow and apple developer forums) mentioned
        // delays or hangs when calling `AAAttribution.attributionToken()`, with
        // questions as to if the call performs network requests in some way.
        // Apple's documentation is mum on the matter.
        // In any case, we run this detached to avoid any strangeness in that way.
        logger.debug("Requesting ad attribution token")
        let attributionTokenTask = Task.detached {
            try AAAttribution.attributionToken()
        }
        let token = try await attributionTokenTask.value
        logger.debug("Received ad attribution token: \(token)")
        return token
    }

    /// Given an Apple Search Ads attribution `token` `String`, attempts to asynchronously
    /// fetch an attribution record from Apple's v1 API endpoint.
    ///
    /// When running on Simulator or from Xcode, Apple's API returns what is essentially
    /// a mock payload (see `isMockData`), though this particular mock data isn't
    /// documented as a guaranteed response.  In any case, we detect it as a mock data
    /// response and throw `AttributionPayloadFetchError.mockDataReceived` in
    /// that situation.
    ///
    /// If all goes well, we return an optional `AttributionPayload`.
    ///
    /// This result can be `nil` if the API call succeeds (HTTP status code 200) and the result is
    /// a JSON dictionary, but the top-level of the dictionary does not contain an `attribution`
    /// key, or the value of that key is anything other than `true`.
    private func fetchAttributionRecord(_ token: String) async throws -> AttributionPayload? {
        logger.debug("Fetching attribution record")
        let url = URL(string: "https://api-adservices.apple.com/api/v1/")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = token.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let urlResponse = response as? HTTPURLResponse else {
            // throw
            fatalError("Response is not HTTPURLResponse")
        }

        logger.debug("HTTP status code: \(urlResponse.statusCode).  All headers: \(urlResponse.allHeaderFields)")

        /// Logs JSON and non-JSON responses
        func logJSON() {
            guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if let text = String(data: data, encoding: .utf8) {
                    logger.log("Non-JSON response: \(text)")
                } else {
                    logger.log("Non-JSON, non-text response data of \(data.count) bytes")
                }
                return
            }
            logger.debug("JSON object is \(jsonObject)")
        }

        switch urlResponse.statusCode {
        case 200:
            // successful response
            let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let attribution = jsonObject["attribution"] as? Bool, attribution == true {
                let payload = try JSONDecoder().decode(AttributionPayload.self, from: data)
                let payloadText = "\(payload)"
                if payload.isMockData {
                    logger.warning("Attribution received.  *** MOCK PAYLOAD: \(payloadText)")
                    logJSON()
                    throw AttributionPayloadFetchError.mockDataReceived
                } else {
                    logger.log("Attribution received.  Payload: \(payloadText)")
                    return payload
                }
            } else {
                logger.log("API call successful, but `attribution` key is missing or has a non-`true` value")
                logJSON()
                return nil
            }

        case 400:
            // invalid token
            throw AttributionPayloadFetchError.status400InvalidToken

        case 404:
            // Not found - could be retried
            throw AttributionPayloadFetchError.status404NotFound

        case 500:
            // Server unavailable
            throw AttributionPayloadFetchError.status500ServerUnavailable

        default:
            let statusCodeText = "\(urlResponse.statusCode)"
            logger.error("Received unexpected HTTP status code \(statusCodeText) - response ignored")
            logJSON()
            throw AttributionPayloadFetchError.unknownHTTPStatusCodeInResponse
        }
    }

    /// A closure that's called when a new attribution payload (`AttributionPayload`) is received from Apple's API
    private let onNewAttributionPayloadReceived: (AttributionPayload) -> Void

    /// A closure that's called when a previously-received and saved attribution payload (`AttributionPayload`)
    /// is loaded from `UserDefaults` storage
    private let onAttributionPayloadLoaded: (AttributionPayload) -> Void


    /// Initializes a new instance, which begins its work asynchronously.
    ///
    /// Upon initialization, we check for any previously saved attribution payload.  If one is found, it is loaded
    /// and stored in `attributionPayload`, and the `onAttributionPayloadLoaded` closure is
    /// called, with the just-loaded `AttributionPayload`.
    ///
    /// After that, we attempt to fetch an ad attribution token via Apple's APIs.
    ///
    /// On success:
    ///    The newly-received `AttributionPayload` is compared with any previously saved attribution payload
    ///    If it differs or if no saved payload exists, the new payload is saved, stored in `attributionPayload`,
    ///    and then the closure for `onAttributinoPayloadLoaded` is called, followed by the closure for
    ///    `onNewAttributionPayloadReceived`.
    ///
    /// - Parameters:
    ///   - onAttributionPayloadLoaded: A closure to be called any time an `AttributionPayload` is
    ///     updated or changed, such as when a previously received saved payload has been loaded, or when
    ///     the payload changes after an update from a call to Apple's API.
    ///
    ///   - onNewAttributionPayloadReceived: A closure to be called whenever a new `AttributionPayload`
    ///     is received from a call to Apple's API.  Note that this closure will only be called if we have never received
    ///     one previously, or if its contents have changed.
    ///
    /// On failure:
    ///    If any errors occur when fetching the `AttributionPayload`, the instance `@Published` variable `error`
    ///    will be updated.  After an error, the fetch will not be retried.  Create a new instance to retry.
    ///
    public init(_ onAttributionPayloadLoaded: @escaping (AttributionPayload) -> Void, onNewAttributionPayloadReceived: @escaping (AttributionPayload) -> Void) {
        self.onAttributionPayloadLoaded = onAttributionPayloadLoaded
        self.onNewAttributionPayloadReceived = onNewAttributionPayloadReceived

        Task.detached {
            if let savedAttributionPayload = self.savedAttributionPayload {
                DispatchQueue.main.async {
                    self.attributionPayload = savedAttributionPayload
                    self.onAttributionPayloadLoaded(savedAttributionPayload)
                }
            }
            do {
                let token = try await self.getAttributionToken()
                do {
                    let payload = try await self.fetchAttributionRecord(token)
                    if let payload, payload != self.savedAttributionPayload {
                        DispatchQueue.main.async {
                            self.attributionPayload = payload
                            self.savedAttributionPayload = payload
                            self.onAttributionPayloadLoaded(payload)
                            self.onNewAttributionPayloadReceived(payload)
                        }
                    }
                } catch {
                    logger.error("Error fetching ad attribution record: \(error)")
                }
            } catch {
                logger.error("Error getting ad attribution token: \(error)")
            }
        }
    }
}
