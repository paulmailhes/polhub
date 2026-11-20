import Foundation
import Network

/// A request, as the server read it. Header names are lowercased.
public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// The request line and headers of an HTTP/1.1 request, up to the blank line; nil when it is not one.
    static func head(_ text: String) -> HTTPRequest? {
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ", omittingEmptySubsequences: true) ?? []
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), let components = URLComponents(string: String(parts[1])) else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return HTTPRequest(method: String(parts[0]), path: components.path, query: query, headers: headers)
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json(_ body: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: body)
    }

    public static func file(_ body: Data, type: String, name: String) -> HTTPResponse {
        let safe = name.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        return HTTPResponse(status: 200, headers: ["Content-Type": type, "Content-Disposition": "inline; filename=\"\(safe)\""], body: body)
    }

    var reason: String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 503: "Service Unavailable"
        default: status < 400 ? "OK" : "Error"
        }
    }

    /// The bytes sent: the status line, the headers, the body; the connection closes after it.
    var bytes: Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = "close"
        all["Cache-Control"] = "no-store"
        for (name, value) in all.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// A small HTTP/1.1 server for Polhub's iPhone (20/11): it listens on the Mac's loopback only (`127.0.0.1`), never on
/// a network; `tailscale serve` publishes it on Paul's tailnet. One request per connection, a body of 20 MB at most.
public final class HTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    /// The largest body read: a mail with its files.
    public static let maxBody = 20 * 1_024 * 1_024
    static let maxHead = 64 * 1_024

    private let requestedPort: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: "fr.paulmailhes.polhub.serveur")
    private var listener: NWListener?

    /// `port` 0: any free port (the tests).
    public init(port: UInt16, handler: @escaping Handler) {
        requestedPort = port
        self.handler = handler
    }

    /// Starts listening; the port it listens on.
    public func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: requestedPort) ?? .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                case .cancelled:
                    once.run { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1_024) { [weak self] data, _, complete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch Self.parse(buffer) {
            case .incomplete where error == nil && !complete:
                self.read(connection, buffer: buffer)
            case .incomplete, .invalid:
                self.send(HTTPResponse(status: 400), on: connection)
            case .tooLarge:
                self.send(HTTPResponse(status: 413), on: connection)
            case .request(let request):
                let handler = self.handler
                Task {
                    let response = await handler(request)
                    self.send(response, on: connection)
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    enum Parsed {
        case incomplete, invalid, tooLarge
        case request(HTTPRequest)
    }

    /// What the bytes received so far make: a whole request, not yet, or never one.
    static func parse(_ buffer: Data) -> Parsed {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHead ? .tooLarge : .incomplete
        }
        guard end.lowerBound <= maxHead, let text = String(data: buffer[..<end.lowerBound], encoding: .utf8),
              var request = HTTPRequest.head(text) else { return .invalid }
        let length = Int(request.header("content-length") ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        guard length <= maxBody else { return .tooLarge }
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        request.body = Data(body.prefix(length))
        return .request(request)
    }
}

/// Runs its block once, whatever thread asks.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        block()
    }
}
