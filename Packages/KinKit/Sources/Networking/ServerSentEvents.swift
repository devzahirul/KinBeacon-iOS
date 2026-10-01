import Foundation

public struct ServerSentEvent: Hashable, Sendable {
    public var event: String
    public var data: String
    public var id: String?

    public init(event: String = "message", data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental `text/event-stream` parser (WHATWG spec subset: `event`, `data`, `id`, comments, multi-line data).
///
/// SSE over `URLSession.bytes` was chosen over WebSockets for the parent's live feed: it is plain HTTP (works through
/// school/corporate proxies), resumes with `Last-Event-ID`, and the traffic is one-directional anyway — commands go
/// the other way over regular POSTs.
public struct ServerSentEventParser: Sendable {
    private var event = ""
    private var dataLines: [String] = []
    private var id: String?

    public init() {}

    /// Feeds one line; returns an event when a blank line completes one.
    public mutating func consume(_ line: String) -> ServerSentEvent? {
        if line.isEmpty {
            defer { event = ""; dataLines = []; id = nil }
            guard !dataLines.isEmpty else { return nil }
            return ServerSentEvent(event: event.isEmpty ? "message" : event, data: dataLines.joined(separator: "\n"), id: id)
        }
        if line.hasPrefix(":") {
            return nil
        }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") {
                value = value.dropFirst()
            }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": dataLines.append(String(value))
        case "id": id = String(value)
        default: break
        }
        return nil
    }

    public static func events(from lines: AsyncThrowingStream<String, any Error>) -> AsyncThrowingStream<ServerSentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = ServerSentEventParser()
                do {
                    for try await line in lines {
                        if let event = parser.consume(line) {
                            continuation.yield(event)
                        }
                    }
                    // A stream that ends without a trailing blank line still delivers its last event.
                    if let event = parser.consume("") {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
