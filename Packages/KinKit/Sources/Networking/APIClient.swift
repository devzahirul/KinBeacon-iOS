public import Foundation
public import KinCore
import Domain

/// The seam between the client and the network. `URLSession` conforms; tests inject a stub.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, any Error>, URLResponse)
}

extension URLSession: HTTPTransport {
    public func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, any Error>, URLResponse) {
        let (bytes, response) = try await bytes(for: request)
        let stream = AsyncThrowingStream<String, any Error> { continuation in
            // Not `bytes.lines`: `AsyncLineSequence` drops empty lines, and an empty line is exactly the SSE event
            // delimiter. Split on LF ourselves (AsyncBytes is internally buffered, so this is not a syscall per byte).
            // Lossy UTF-8 decoding is intended for a text stream.
            let task = Task {
                do {
                    var buffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            if buffer.last == UInt8(ascii: "\r") {
                                buffer.removeLast()
                            }
                            // swiftlint:disable:next optional_data_string_conversion
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        // swiftlint:disable:next optional_data_string_conversion
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, response)
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
}

/// A typed request description. Building one is pure (unit-tested); sending it is the client's job.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    /// Sent as `Idempotency-Key` so the server de-duplicates outbox retries of the same POST.
    public var idempotencyKey: String?

    public init(method: HTTPMethod = .get, path: String, query: [URLQueryItem] = [], body: Data? = nil, idempotencyKey: String? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.idempotencyKey = idempotencyKey
    }

    /// GETs, PUTs and keyed POSTs can be retried safely.
    public var isRetriable: Bool {
        method != .post || idempotencyKey != nil
    }
}

/// An empty response body.
public struct NoContent: Decodable, Sendable {}

/// async/await HTTP client: auth header, JSON coding, error mapping, and bounded retries for transient failures.
public struct APIClient: Sendable {
    public var baseURL: URL
    private let transport: any HTTPTransport
    private let token: @Sendable () async -> String?
    private let backoff: ExponentialBackoff
    private let maxRetries: Int

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSession(configuration: .kinDefault),
        token: @escaping @Sendable () async -> String? = { nil },
        backoff: ExponentialBackoff = ExponentialBackoff(base: .milliseconds(400), maximum: .seconds(4)),
        maxRetries: Int = 2
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.token = token
        self.backoff = backoff
        self.maxRetries = maxRetries
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    public func makeRequest(_ endpoint: Endpoint<some Decodable & Sendable>) async throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false) else {
            throw KinError.invalidResponse
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let url = components.url else { throw KinError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = endpoint.idempotencyKey {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        if let token = await token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try await makeRequest(endpoint)
        var attempt = 0
        while true {
            do {
                return try await perform(request, as: Response.self)
            } catch let error as KinError where error.isTransient && endpoint.isRetriable && attempt < maxRetries {
                try await Task.sleep(for: backoff.delay(forAttempt: attempt))
                attempt += 1
            }
        }
    }

    /// Opens a Server-Sent Events stream (`text/event-stream`).
    public func events(path: String) async throws -> AsyncThrowingStream<ServerSentEvent, any Error> {
        var request = try await makeRequest(Endpoint<NoContent>(path: path))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity
        let (lines, response) = try await transport.lines(for: request)
        try Self.validate(response)
        return ServerSentEventParser.events(from: lines)
    }

    private func perform<Response: Decodable>(_ request: URLRequest, as type: Response.Type) async throws -> Response {
        let state = Perf.begin("network.request")
        defer { Perf.end("network.request", state) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        }
        try Self.validate(response)
        if Response.self == NoContent.self, let empty = NoContent() as? Response {
            return empty
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            Log.network
                .error(
                    "Decoding \(String(describing: Response.self), privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            throw KinError.invalidResponse
        }
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw KinError.invalidResponse }
        switch http.statusCode {
        case 200 ..< 300: return
        case 401, 403: throw KinError.unauthorized
        case 404: throw KinError.notFound
        default: throw KinError.server(status: http.statusCode)
        }
    }

    static func map(_ error: URLError) -> KinError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
            .offline
        default:
            .server(status: error.errorCode)
        }
    }
}

public extension URLSessionConfiguration {
    /// Waits for connectivity instead of failing instantly, and never uses the URL cache for live family data.
    static var kinDefault: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "KinBeacon-iOS/1.0"]
        return configuration
    }
}
