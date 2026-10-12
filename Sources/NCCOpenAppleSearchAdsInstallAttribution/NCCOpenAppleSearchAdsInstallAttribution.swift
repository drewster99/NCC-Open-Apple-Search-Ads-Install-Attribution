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
import Combine
import AdServices
import OSLog


private let logger = Logger(subsystem: "NCCOpenAppleSearchAdsInstallAttribution", category: "NCCOpenAppleSearchAdsInstallAttribution")

/// Fetches advertising install attribution record for app instances that were installed with Apple Search Ads
@MainActor
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

        /// No record was found, either because it isn't available yet or because the token is more than
        /// 24 hours old.  Thrown only after Apple's recommended retries (3 attempts, 5 seconds apart) fail.
        case status404NotFound = "No record found for token"

        /// Your request might be valid, but you'll need to retry it later
        case status500ServerUnavailable = "The Apple Search Ads server is temporarily down or unavailable"

        public var errorDescription: String? { rawValue }
    }

    /// Apple Search Ads app install attribution payload returned from Apple's server
    @Published public var attributionPayload: AttributionPayload?

    /// The most recent `Error`, if any, or `nil`, if no error has occurred
    @Published public var error: Swift.Error?

    private static let savedAttributionPayloadUserDefaultsKey = "NCCOpenAppleSearchAdsInstallAttribution_savedAttributionPayload"
    private var savedAttributionPayload: AttributionPayload? {
        get {
            guard let data = userDefaults.data(forKey: Self.savedAttributionPayloadUserDefaultsKey) else {
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
                userDefaults.removeObject(forKey: Self.savedAttributionPayloadUserDefaultsKey)
                return
            }
            do {
                let data = try JSONEncoder().encode(newValue)
                userDefaults.set(data, forKey: Self.savedAttributionPayloadUserDefaultsKey)
            } catch {
                logger.error("Unable to JSON encode savedAttributionPayload for saving: \(error)")
                return
            }
        }
    }

    /// Runs `AAAttribution.attributionToken()`, which is synchronous and has been reported to stall
    /// (Apple doesn't document whether it touches the network), so it must not block a Swift Concurrency thread.
    nonisolated private static let attributionTokenQueue = DispatchQueue(label: "NCCOpenAppleSearchAdsInstallAttribution.attributionToken")

    /// Apple's attribution API endpoint
    nonisolated private static let attributionAPIURLString = "https://api-adservices.apple.com/api/v1/"

    /// Fetches the app's attribution token, returning it as a `String` or throwing if an error occurs
    nonisolated static func getAttributionToken() async throws -> String {
        logger.debug("Requesting ad attribution token")
        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Swift.Error>) in
            attributionTokenQueue.async {
                continuation.resume(with: Result { try AAAttribution.attributionToken() })
            }
        }
        logger.debug("Received ad attribution token: \(token, privacy: .private)")
        return token
    }

    /// Fetches the attribution record for `token` from Apple's API, retrying a 404 per `notFoundRetryPolicy`.
    ///
    /// Apple answers 404 when the record isn't available yet, which is common right after install, so a 404 is
    /// retried. Every other failure is thrown immediately.
    ///
    /// - Returns: The payload, or `nil` if Apple reports the install as not attributed (`attribution` is `false`).
    /// - Throws: `AttributionPayloadFetchError`, a `URLError`, a `DecodingError` for a malformed response, or
    ///   `CancellationError` if cancelled while waiting to retry.
    nonisolated static func fetchAttributionRecord(_ token: String, using urlSession: URLSession, notFoundRetryPolicy: NotFoundRetryPolicy) async throws -> AttributionPayload? {
        var attempt = 1
        while true {
            do {
                return try await requestAttributionRecord(token, using: urlSession)
            } catch AttributionPayloadFetchError.status404NotFound where attempt < notFoundRetryPolicy.maximumAttempts {
                logger.log("No attribution record yet (attempt \(attempt) of \(notFoundRetryPolicy.maximumAttempts)); retrying in \(notFoundRetryPolicy.delay)")
                try await Task.sleep(for: notFoundRetryPolicy.delay)
                attempt += 1
            }
        }
    }

    /// The `attribution` flag Apple includes in every successful response, attributed or not
    private struct AttributionStatus: Decodable {
        let attribution: Bool
    }

    /// Makes a single request to Apple's attribution API for `token`.
    ///
    /// When developer mode is on, Apple's API returns a test payload (see `isMockData`). We detect it and throw
    /// `AttributionPayloadFetchError.mockDataReceived` rather than report it as a real attribution.
    private nonisolated static func requestAttributionRecord(_ token: String, using urlSession: URLSession) async throws -> AttributionPayload? {
        logger.debug("Fetching attribution record")
        guard let url = URL(string: attributionAPIURLString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(token.utf8)
        let (data, response) = try await urlSession.data(for: request)
        guard let urlResponse = response as? HTTPURLResponse else {
            throw AttributionPayloadFetchError.responseIsNotHTTPURLResponse
        }

        logger.debug("HTTP status code: \(urlResponse.statusCode)")

        func logResponseBody() {
            logger.log("Response body (\(data.count) bytes): \(String(decoding: data, as: UTF8.self), privacy: .private)")
        }

        func decode<Decoded: Decodable>(_ type: Decoded.Type) throws -> Decoded {
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                logger.error("Unable to decode attribution response: \(error)")
                logResponseBody()
                throw error
            }
        }

        switch urlResponse.statusCode {
        case 200:
            guard try decode(AttributionStatus.self).attribution else {
                logger.log("API call successful; install is not attributed")
                return nil
            }
            let payload = try decode(AttributionPayload.self)
            if payload.isMockData {
                logger.warning("Attribution received.  *** MOCK PAYLOAD: \(String(describing: payload), privacy: .private)")
                throw AttributionPayloadFetchError.mockDataReceived
            }
            logger.log("Attribution received.  Payload: \(String(describing: payload), privacy: .private)")
            return payload

        case 400:
            throw AttributionPayloadFetchError.status400InvalidToken

        case 404:
            throw AttributionPayloadFetchError.status404NotFound

        case 500:
            throw AttributionPayloadFetchError.status500ServerUnavailable

        default:
            logger.error("Received unexpected HTTP status code \(urlResponse.statusCode) - response ignored")
            logResponseBody()
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
    ///    and then the closure for `onAttributionPayloadLoaded` is called, followed by the closure for
    ///    `onNewAttributionPayloadReceived`.
    ///
    ///    Apple's API answers 404 when the record isn't available yet, which is common right after install.
    ///    Following Apple's guidance, a 404 is retried up to 3 times in total, 5 seconds apart.
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
    ///    will be updated.  Apart from the 404 retries above, the fetch will not be retried.  Create a new
    ///    instance to retry.  When developer mode is on, Apple returns a test payload; it is not saved or
    ///    reported, and `error` is set to `AttributionPayloadFetchError.mockDataReceived`.
    ///
    public init(_ onAttributionPayloadLoaded: @escaping (AttributionPayload) -> Void, onNewAttributionPayloadReceived: @escaping (AttributionPayload) -> Void) {
        self.urlSession = .shared
        self.userDefaults = .standard
        self.onAttributionPayloadLoaded = onAttributionPayloadLoaded
        self.onNewAttributionPayloadReceived = onNewAttributionPayloadReceived
        startFetching(
            attributionTokenProvider: { try await NCCOpenAppleSearchAdsInstallAttribution.getAttributionToken() },
            notFoundRetryPolicy: .appleRecommended
        )
    }

    /// Supplies the AdServices attribution token. Injectable so tests can run without AdServices.
    typealias AttributionTokenProvider = @Sendable () async throws -> String

    /// How to retry when Apple's API answers 404, which it does when the record isn't available yet.
    struct NotFoundRetryPolicy: Sendable {
        /// Total number of requests, including the first
        let maximumAttempts: Int
        /// Wait between attempts
        let delay: Duration

        /// Apple: "initiate retries at intervals of 5 seconds, with a maximum of 3 attempts"
        static let appleRecommended = NotFoundRetryPolicy(maximumAttempts: 3, delay: .seconds(5))
    }

    /// The fetch started by `init`. Held so tests can await completion.
    private(set) var fetchTask: Task<Void, Never>?

    private let urlSession: URLSession
    private let userDefaults: UserDefaults

    /// Dependency-injecting initializer for tests.
    init(
        attributionTokenProvider: @escaping AttributionTokenProvider,
        urlSession: URLSession,
        userDefaults: UserDefaults,
        notFoundRetryPolicy: NotFoundRetryPolicy,
        onAttributionPayloadLoaded: @escaping (AttributionPayload) -> Void,
        onNewAttributionPayloadReceived: @escaping (AttributionPayload) -> Void
    ) {
        self.urlSession = urlSession
        self.userDefaults = userDefaults
        self.onAttributionPayloadLoaded = onAttributionPayloadLoaded
        self.onNewAttributionPayloadReceived = onNewAttributionPayloadReceived
        startFetching(attributionTokenProvider: attributionTokenProvider, notFoundRetryPolicy: notFoundRetryPolicy)
    }

    /// Loads any saved payload, then fetches the current one. Called once, from `init`.
    private func startFetching(attributionTokenProvider: @escaping AttributionTokenProvider, notFoundRetryPolicy: NotFoundRetryPolicy) {
        fetchTask = Task {
            // Load saved attribution payload if exists
            if let savedAttributionPayload = self.savedAttributionPayload {
                self.attributionPayload = savedAttributionPayload
                self.onAttributionPayloadLoaded(savedAttributionPayload)
            }

            let token: String
            do {
                token = try await attributionTokenProvider()
            } catch {
                logger.error("Error getting ad attribution token: \(error)")
                self.error = error
                return
            }
            do {
                let payload = try await Self.fetchAttributionRecord(token, using: self.urlSession, notFoundRetryPolicy: notFoundRetryPolicy)
                if let payload, payload != self.savedAttributionPayload {
                    self.attributionPayload = payload
                    self.savedAttributionPayload = payload
                    self.onAttributionPayloadLoaded(payload)
                    self.onNewAttributionPayloadReceived(payload)
                }
            } catch {
                logger.error("Error fetching ad attribution record: \(error)")
                self.error = error
            }
        }
    }
}
