import Foundation
import Testing
@testable import NCCOpenAppleSearchAdsInstallAttribution

/// Counts closure calls made by an `NCCOpenAppleSearchAdsInstallAttribution` instance
@MainActor
final class CallbackRecorder {
    var loadedPayloads: [Attribution.AttributionPayload] = []
    var newPayloads: [Attribution.AttributionPayload] = []
}

@MainActor
@Suite("NCCOpenAppleSearchAdsInstallAttribution instance")
struct AttributionInstanceTests {
    let session = StubURLProtocol.makeSession()
    let token = Fixtures.makeUniqueToken()
    let userDefaults: UserDefaults
    let recorder = CallbackRecorder()

    init() throws {
        userDefaults = try Fixtures.makeIsolatedUserDefaults()
    }

    /// Creates an instance and waits for its fetch to finish
    private func makeFinishedInstance(
        attributionTokenProvider: @escaping Attribution.AttributionTokenProvider
    ) async -> Attribution {
        let recorder = recorder
        let instance = Attribution(
            attributionTokenProvider: attributionTokenProvider,
            urlSession: session,
            userDefaults: userDefaults,
            notFoundRetryPolicy: Fixtures.fastRetryPolicy,
            onAttributionPayloadLoaded: { recorder.loadedPayloads.append($0) },
            onNewAttributionPayloadReceived: { recorder.newPayloads.append($0) }
        )
        await instance.fetchTask?.value
        return instance
    }

    private func makeFinishedInstance() async -> Attribution {
        let token = token
        return await makeFinishedInstance(attributionTokenProvider: { token })
    }

    @Test("A token failure is published in error")
    func tokenFailurePublished() async throws {
        let instance = await makeFinishedInstance(attributionTokenProvider: { throw FixtureError.tokenUnavailable })
        #expect(instance.error is FixtureError)
        #expect(instance.attributionPayload == nil)
        #expect(recorder.loadedPayloads.isEmpty)
        #expect(recorder.newPayloads.isEmpty)
    }

    @Test("An API failure is published in error")
    func apiFailurePublished() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 400, body: "")], forToken: token)
        let instance = await makeFinishedInstance()
        #expect(instance.error as? FetchError == .status400InvalidToken)
        #expect(instance.attributionPayload == nil)
    }

    @Test("A response that isn't an HTTP response is published in error, not a crash")
    func nonHTTPResponsePublished() async throws {
        StubURLProtocol.enqueue([.nonHTTP(body: Fixtures.clickPayloadJSON)], forToken: token)
        let instance = await makeFinishedInstance()
        #expect(instance.error as? FetchError == .responseIsNotHTTPURLResponse)
    }

    @Test("Apple's developer-mode test payload is published in error and not saved")
    func mockPayloadPublished() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.mockPayloadJSON)], forToken: token)
        let instance = await makeFinishedInstance()
        #expect(instance.error as? FetchError == .mockDataReceived)
        #expect(instance.attributionPayload == nil)
        #expect(recorder.newPayloads.isEmpty)
    }

    @Test("Not attributed: no payload, no error, no callbacks")
    func notAttributed() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.notAttributedJSON)], forToken: token)
        let instance = await makeFinishedInstance()
        #expect(instance.error == nil)
        #expect(instance.attributionPayload == nil)
        #expect(recorder.loadedPayloads.isEmpty)
        #expect(recorder.newPayloads.isEmpty)
    }

    @Test("A new payload is published, saved, and reported to both closures once")
    func newPayload() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.clickPayloadJSON)], forToken: token)
        let instance = await makeFinishedInstance()
        #expect(instance.error == nil)
        #expect(instance.attributionPayload?.orgId == 40669820)
        #expect(recorder.loadedPayloads.count == 1)
        #expect(recorder.newPayloads.count == 1)
    }

    @Test("On a later launch the saved payload is loaded, and an unchanged payload isn't reported as new")
    func savedPayloadReloaded() async throws {
        StubURLProtocol.enqueue([
            .http(statusCode: 200, body: Fixtures.clickPayloadJSON),
            .http(statusCode: 200, body: Fixtures.clickPayloadJSON),
        ], forToken: token)
        _ = await makeFinishedInstance()
        let secondLaunchRecorder = CallbackRecorder()
        let token = token
        let secondLaunch = Attribution(
            attributionTokenProvider: { token },
            urlSession: session,
            userDefaults: userDefaults,
            notFoundRetryPolicy: Fixtures.fastRetryPolicy,
            onAttributionPayloadLoaded: { secondLaunchRecorder.loadedPayloads.append($0) },
            onNewAttributionPayloadReceived: { secondLaunchRecorder.newPayloads.append($0) }
        )
        await secondLaunch.fetchTask?.value
        #expect(secondLaunch.attributionPayload?.orgId == 40669820)
        #expect(secondLaunchRecorder.loadedPayloads.count == 1)
        #expect(secondLaunchRecorder.newPayloads.isEmpty)
    }

    @Test("A saved payload is still loaded when the fetch fails")
    func savedPayloadSurvivesFetchFailure() async throws {
        StubURLProtocol.enqueue([.http(statusCode: 200, body: Fixtures.clickPayloadJSON)], forToken: token)
        _ = await makeFinishedInstance()
        let secondLaunch = await makeFinishedInstance(attributionTokenProvider: { throw FixtureError.tokenUnavailable })
        #expect(secondLaunch.attributionPayload?.orgId == 40669820)
        #expect(secondLaunch.error is FixtureError)
    }
}
