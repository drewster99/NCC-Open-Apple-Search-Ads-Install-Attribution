import Foundation
import Testing
@testable import NCCOpenAppleSearchAdsInstallAttribution

@Suite("fetchAttributionRecord")
struct FetchAttributionRecordTests {
    let session = StubURLProtocol.makeSession()
    let token = Fixtures.makeUniqueToken()

    private func fetch() async throws -> Attribution.AttributionPayload? {
        try await Attribution.fetchAttributionRecord(token, using: session, notFoundRetryPolicy: Fixtures.fastRetryPolicy)
    }

    @Test("Sends the token as a text/plain POST body")
    func requestFormat() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.notAttributedJSON)], forToken: token)
        _ = try await fetch()
        let requests = StubURLProtocol.requests(forToken: token)
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.contentType == "text/plain")
        #expect(requests.first?.body == token)
    }

    @Test("200 with attribution true returns the payload")
    func attributed() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.clickPayloadJSON)], forToken: token)
        let payload = try #require(try await fetch())
        #expect(payload.attribution)
        #expect(payload.orgId == 40669820)
        #expect(payload.campaignId == 542370539)
        #expect(payload.adGroupId == 542317095)
        #expect(payload.keywordId == 87675432)
        #expect(payload.adId == 542317136)
        #expect(payload.conversionType == "Download")
        #expect(payload.countryOrRegion == "US")
        #expect(payload.clickDate == "2020-04-08T17:17Z")
    }

    @Test("200 with attribution false returns nil")
    func notAttributed() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.notAttributedJSON)], forToken: token)
        #expect(try await fetch() == nil)
    }

    @Test("200 with Apple's developer-mode test payload throws mockDataReceived")
    func mockPayload() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.mockPayloadJSON)], forToken: token)
        await #expect(throws: FetchError.mockDataReceived) { try await fetch() }
    }

    @Test("200 whose body is not a JSON object throws instead of reporting 'not attributed'")
    func bodyIsNotAnObject() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: "[]")], forToken: token)
        await #expect(throws: (any Error).self) { try await fetch() }
    }

    @Test("200 whose body is not JSON throws")
    func bodyIsNotJSON() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: "<html>oops</html>")], forToken: token)
        await #expect(throws: (any Error).self) { try await fetch() }
    }

    @Test("200 without an attribution key throws instead of reporting 'not attributed'")
    func missingAttributionKey() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: #"{"orgId":1}"#)], forToken: token)
        await #expect(throws: (any Error).self) { try await fetch() }
    }

    @Test("400 throws status400InvalidToken without retrying")
    func invalidToken() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 400, body: "")], forToken: token)
        await #expect(throws: FetchError.status400InvalidToken) { try await fetch() }
        #expect(StubURLProtocol.requests(forToken: token).count == 1)
    }

    @Test("500 throws status500ServerUnavailable without retrying")
    func serverUnavailable() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 500, body: "")], forToken: token)
        await #expect(throws: FetchError.status500ServerUnavailable) { try await fetch() }
        #expect(StubURLProtocol.requests(forToken: token).count == 1)
    }

    @Test("Undocumented status throws unknownHTTPStatusCodeInResponse", arguments: [201, 302, 401, 429, 503])
    func unexpectedStatus(statusCode: Int) async throws {
        StubURLProtocol.enqueue([.http(statusCode: statusCode, body: "")], forToken: token)
        await #expect(throws: FetchError.unknownHTTPStatusCodeInResponse) { try await fetch() }
    }

    @Test("404 is retried, and a later 200 succeeds")
    func notFoundThenFound() async throws {
        StubURLProtocol.enqueue([
            .http(statusCode: 404, body: ""),
            .http(statusCode: 404, body: ""),
            .http(statusCode: 200, body: Fixtures.clickPayloadJSON),
        ], forToken: token)
        let payload = try await fetch()
        #expect(payload?.orgId == 40669820)
        #expect(StubURLProtocol.requests(forToken: token).count == 3)
    }

    @Test("404 on every attempt throws status404NotFound after exactly maximumAttempts requests")
    func notFoundEveryTime() async throws {
        StubURLProtocol.enqueue(Array(repeating: .http(statusCode: 404, body: ""), count: 5), forToken: token)
        await #expect(throws: FetchError.status404NotFound) { try await fetch() }
        #expect(StubURLProtocol.requests(forToken: token).count == Fixtures.fastRetryPolicy.maximumAttempts)
    }

    @Test("A 404 followed by a non-retryable error stops retrying")
    func notFoundThenInvalidToken() async throws {
        StubURLProtocol.enqueue([
            .http(statusCode: 404, body: ""),
            .http(statusCode: 400, body: ""),
            .http(statusCode: 200, body: Fixtures.clickPayloadJSON),
        ], forToken: token)
        await #expect(throws: FetchError.status400InvalidToken) { try await fetch() }
        #expect(StubURLProtocol.requests(forToken: token).count == 2)
    }

    @Test("Cancellation during the retry wait stops retrying")
    func cancelledWhileWaitingToRetry() async throws {
        StubURLProtocol.enqueue(Array(repeating: .http(statusCode: 404, body: ""), count: 3), forToken: token)
        let slowRetry = Attribution.NotFoundRetryPolicy(maximumAttempts: 3, delay: .seconds(30))
        let fetchTask = Task { [token, session] in
            try await Attribution.fetchAttributionRecord(token, using: session, notFoundRetryPolicy: slowRetry)
        }
        try await Task.sleep(for: .milliseconds(300))
        fetchTask.cancel()
        await #expect(throws: CancellationError.self) { try await fetchTask.value }
        #expect(StubURLProtocol.requests(forToken: token).count == 1)
    }
}
