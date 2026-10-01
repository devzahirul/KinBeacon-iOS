@testable import Domain
import Foundation
import KinCore
@testable import Networking
import Testing
import TestSupport

/// Scripted transport: returns canned responses in order and records requests.
actor StubTransport: HTTPTransport {
    var responses: [Result<(Int, Data), URLError>]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Result<(Int, Data), URLError>]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let next = responses.isEmpty ? .success((200, Data("{}".utf8))) : responses.removeFirst()
        switch next {
        case let .success((status, body)):
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case let .failure(error):
            throw error
        }
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, any Error>, URLResponse) {
        let lines = ["event: snapshot", "data: {\"a\":1}", "", ": keep-alive", "data: hello", "data: world", ""]
        let stream = AsyncThrowingStream<String, any Error> { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }
        return (stream, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

struct Echo: Codable, Equatable {
    var batteryLevel: Double
}

@Suite("APIClient")
struct APIClientTests {
    let base = URL(string: "https://api.kinbeacon.app")!

    func client(_ transport: StubTransport, retries: Int = 2) -> APIClient {
        APIClient(
            baseURL: base,
            transport: transport,
            token: { "token-123" },
            backoff: ExponentialBackoff(base: .milliseconds(1), jitter: false),
            maxRetries: retries
        )
    }

    @Test("Builds authenticated JSON requests with idempotency keys")
    func requestBuilding() async throws {
        let request = try await client(StubTransport([])).makeRequest(Endpoint<NoContent>(
            method: .post,
            path: "v1/me/check-ins",
            query: [URLQueryItem(name: "x", value: "1")],
            body: Data("{}".utf8),
            idempotencyKey: "abc"
        ))
        #expect(request.url?.absoluteString == "https://api.kinbeacon.app/v1/me/check-ins?x=1")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "abc")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Decodes snake_case JSON")
    func decoding() async throws {
        let transport = StubTransport([.success((200, Data(#"{"battery_level":0.5}"#.utf8)))])
        let echo = try await client(transport).send(Endpoint<Echo>(path: "v1/echo"))
        #expect(echo == Echo(batteryLevel: 0.5))
    }

    @Test("Maps HTTP and transport errors to domain errors", arguments: [
        (401, KinError.unauthorized), (404, KinError.notFound), (422, KinError.server(status: 422)),
    ])
    func errorMapping(status: Int, expected: KinError) async {
        let transport = StubTransport([.success((status, Data()))])
        await #expect(throws: expected) { try await client(transport, retries: 0).send(Endpoint<NoContent>(path: "v1/x")) }
    }

    @Test("Offline is reported as a transient error")
    func offline() async {
        let transport = StubTransport([.failure(URLError(.notConnectedToInternet))])
        await #expect(throws: KinError.offline) { try await client(transport, retries: 0).send(Endpoint<NoContent>(path: "v1/x")) }
        #expect(KinError.offline.isTransient)
        #expect(KinError.server(status: 503).isTransient)
        #expect(!KinError.server(status: 400).isTransient)
    }

    @Test("Idempotent requests retry transient failures, unkeyed POSTs don't")
    func retries() async throws {
        let getTransport = StubTransport([.success((503, Data())), .success((200, Data(#"{"battery_level":1}"#.utf8)))])
        _ = try await client(getTransport).send(Endpoint<Echo>(path: "v1/echo"))
        #expect(await getTransport.requests.count == 2)

        let postTransport = StubTransport([.success((503, Data()))])
        await #expect(throws: KinError.server(status: 503)) {
            try await client(postTransport).send(Endpoint<NoContent>(method: .post, path: "v1/x"))
        }
        #expect(await postTransport.requests.count == 1)
    }

    @Test("Server-sent events are parsed from the line stream")
    func sse() async throws {
        var events: [ServerSentEvent] = []
        for try await event in try await client(StubTransport([])).events(path: "v1/family/stream") {
            events.append(event)
        }
        #expect(events == [ServerSentEvent(event: "snapshot", data: #"{"a":1}"#), ServerSentEvent(data: "hello\nworld")])
    }
}

@Suite("SSE parser")
struct ServerSentEventParserTests {
    @Test("Handles ids, comments and fields without a space")
    func fields() {
        var parser = ServerSentEventParser()
        #expect(parser.consume(": comment") == nil)
        #expect(parser.consume("id:42") == nil)
        #expect(parser.consume("event:alert") == nil)
        #expect(parser.consume("data:{}") == nil)
        #expect(parser.consume("") == ServerSentEvent(event: "alert", data: "{}", id: "42"))
        // A blank line without data produces nothing.
        #expect(parser.consume("") == nil)
    }
}
