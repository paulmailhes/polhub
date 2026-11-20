import Foundation
import Testing
@testable import LocalServer

/// The iPhone's server (20/11): on the loopback, one request per connection.
@Suite struct HTTPServerTests {
    @Test func aRequestIsReadWholeAndAnswered() async throws {
        let server = HTTPServer(port: 0) { request in
            let echo = "\(request.method) \(request.path) \(request.query["cle"] ?? "-") \(request.header("Authorization") ?? "-") \(String(decoding: request.body, as: UTF8.self))"
            return .json(Data(echo.utf8))
        }
        let port = try await server.start()
        defer { server.stop() }
        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/v1/mail/thread?cle=a%7Cb")))
        request.httpMethod = "POST"
        request.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("bonjour".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "POST /v1/mail/thread a|b Bearer t bonjour")
    }

    @Test func aBrokenRequestIsRefused() {
        guard case .invalid = HTTPServer.parse(Data("GARBAGE\r\n\r\n".utf8)) else { Issue.record("accepté"); return }
        guard case .incomplete = HTTPServer.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)) else { Issue.record("fini trop tôt"); return }
        guard case .incomplete = HTTPServer.parse(Data("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc".utf8)) else {
            Issue.record("corps incomplet accepté")
            return
        }
        guard case .tooLarge = HTTPServer.parse(Data("POST / HTTP/1.1\r\nContent-Length: 999999999\r\n\r\n".utf8)) else {
            Issue.record("trop gros accepté")
            return
        }
        guard case .request(let request) = HTTPServer.parse(Data("GET /v1/status?a=1 HTTP/1.1\r\nHost: x\r\n\r\n".utf8)) else {
            Issue.record("refusé")
            return
        }
        #expect(request.path == "/v1/status" && request.query == ["a": "1"] && request.header("host") == "x")
    }

    @Test func itListensOnTheLoopbackOnly() async throws {
        let server = HTTPServer(port: 0) { _ in .json(Data("{}".utf8)) }
        let port = try await server.start()
        defer { server.stop() }
        // The Mac's address on its network: nothing answers there. Without a network, nothing to try.
        guard let address = Self.networkAddress() else { return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: config)
        let outside = try? await session.data(from: try #require(URL(string: "http://\(address):\(port)/")))
        #expect(outside == nil)
    }

    /// The Mac's first IPv4 address that is not its loopback.
    static func networkAddress() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (Int32(entry.pointee.ifa_flags) & IFF_LOOPBACK) == 0, (Int32(entry.pointee.ifa_flags) & IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return nil
    }
}
