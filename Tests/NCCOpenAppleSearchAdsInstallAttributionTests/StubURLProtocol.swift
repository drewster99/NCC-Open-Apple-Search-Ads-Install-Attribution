import Foundation

/// A canned reply for one request
enum StubReply: Sendable {
    case http(statusCode: Int, body: String)
    case nonHTTP(body: String)
}

/// A request as `StubURLProtocol` received it
struct RecordedRequest: Sendable {
    let httpMethod: String?
    let contentType: String?
    let body: String
}

/// Serves canned replies to requests, keyed by request body. Each test uses a unique attribution token
/// as the body, so tests running in parallel never see each other's replies.
final class StubURLProtocol: URLProtocol {

    /// A `URLSession` that routes every request through `StubURLProtocol`
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Queues `replies`, served in order, for requests whose body is `token`
    static func enqueue(_ replies: [StubReply], forToken token: String) {
        registry.enqueue(replies, for: token)
    }

    /// Every request received so far whose body is `token`
    static func requests(forToken token: String) -> [RecordedRequest] {
        registry.requests(for: token)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(of: request)
        let recorded = RecordedRequest(
            httpMethod: request.httpMethod,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: body
        )
        guard let url = request.url, let reply = Self.registry.takeNextReply(for: body, recording: recorded) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response: URLResponse
        let replyBody: String
        switch reply {
        case .http(let statusCode, let body):
            guard let httpResponse = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
                return
            }
            response = httpResponse
            replyBody = body
        case .nonHTTP(let body):
            response = URLResponse(url: url, mimeType: "application/json", expectedContentLength: body.utf8.count, textEncodingName: nil)
            replyBody = body
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(replyBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream, not `httpBody`
    private static func readBody(of request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(decoding: body, as: UTF8.self)
        }
        guard let stream = request.httpBodyStream else {
            return ""
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static let registry = Registry()

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [String: [StubReply]] = [:]
        private var recordedRequests: [String: [RecordedRequest]] = [:]

        func enqueue(_ newReplies: [StubReply], for token: String) {
            lock.withLock { replies[token, default: []].append(contentsOf: newReplies) }
        }

        func takeNextReply(for token: String, recording request: RecordedRequest) -> StubReply? {
            lock.withLock {
                recordedRequests[token, default: []].append(request)
                guard var queue = replies[token], !queue.isEmpty else {
                    return nil
                }
                let reply = queue.removeFirst()
                replies[token] = queue
                return reply
            }
        }

        func requests(for token: String) -> [RecordedRequest] {
            lock.withLock { recordedRequests[token] ?? [] }
        }
    }
}
