import Foundation
import Testing
@testable import Inspiration

/// Recorded answers handed to the live session in place of the network: the session's own rules (limit, cut,
/// early stop, no cookie, a browser's name) are tested without leaving the Mac.
final class RecordedAnswers: URLProtocol, @unchecked Sendable {
    struct Answer {
        var status: Int
        var headers: [String: String]
        var chunks: [Data]
        /// Each chunk a few milliseconds after the other, as a slow line would bring them.
        var paced: Bool
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    nonisolated(unsafe) private static var stopped: [String] = []

    static func serve(_ url: String, status: Int = 200, headers: [String: String] = [:], chunks: [Data], paced: Bool = false) {
        lock.withLock { answers[url] = Answer(status: status, headers: headers, chunks: chunks, paced: paced) }
    }

    /// The addresses whose loading was stopped before its end.
    static var stoppedEarly: [String] { lock.withLock { stopped } }

    static func requestsTo(_ url: String) -> [URLRequest] {
        lock.withLock { requests.filter { $0.url?.absoluteString == url } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let answer = Self.lock.withLock { () -> Answer? in
            Self.requests.append(request)
            return request.url.flatMap { Self.answers[$0.absoluteString] }
        }
        guard let url = request.url, let answer,
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard answer.paced else {
            for chunk in answer.chunks { client?.urlProtocol(self, didLoad: chunk) }
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let queue = DispatchQueue(label: "reponses-enregistrees")
        for (index, chunk) in answer.chunks.enumerated() {
            queue.asyncAfter(deadline: .now() + .milliseconds(5 * (index + 1))) { [weak self] in
                guard let self, !self.isStopped else { return }
                self.client?.urlProtocol(self, didLoad: chunk)
                if index == answer.chunks.count - 1 { self.client?.urlProtocolDidFinishLoading(self) }
            }
        }
    }

    private let stateLock = NSLock()
    nonisolated(unsafe) private var stoppedFlag = false
    private var isStopped: Bool { stateLock.withLock { stoppedFlag } }

    override func stopLoading() {
        stateLock.withLock { stoppedFlag = true }
        if let url = request.url?.absoluteString { Self.lock.withLock { Self.stopped.append(url) } }
    }
}

@Suite(.serialized) struct LiveHTTPTests {
    let http = LiveInspirationHTTP(protocolClasses: [RecordedAnswers.self])

    /// A page is read up to its limit and cut there; the status comes back whatever it is.
    @Test func aPageIsCutAtItsLimit() async throws {
        let url = "https://page.exemple.fr/longue"
        RecordedAnswers.serve(url, headers: ["Content-Type": "text/html; charset=utf-8"],
                              chunks: Array(repeating: Data(repeating: 65, count: 1000), count: 10))
        let response = try await http.get(InspirationRequest(url: URL(string: url)!, purpose: .page, limit: 2500))
        #expect(response.status == 200 && response.body.count == 2500 && response.truncated && response.contentType == "text/html")
        let refused = "https://www.linkedin.com/company/exemple-refuse/"
        RecordedAnswers.serve(refused, status: 999, chunks: [Data()])
        #expect(try await http.get(InspirationRequest(url: URL(string: refused)!, purpose: .page, limit: 1000)).status == 999)
    }

    /// An image over its limit is refused, announced or not.
    @Test func anImageOverItsLimitIsRefused() async throws {
        let announced = "https://images.exemple.fr/annoncee.jpg"
        RecordedAnswers.serve(announced, headers: ["Content-Length": "50000", "Content-Type": "image/jpeg"], chunks: [Data(repeating: 1, count: 50_000)])
        await #expect(throws: InspirationFetchError.tooLarge) {
            try await http.get(InspirationRequest(url: URL(string: announced)!, purpose: .image, limit: 10_000))
        }
        let streamed = "https://images.exemple.fr/sans-taille.jpg"
        RecordedAnswers.serve(streamed, chunks: Array(repeating: Data(repeating: 1, count: 4000), count: 5))
        await #expect(throws: InspirationFetchError.tooLarge) {
            try await http.get(InspirationRequest(url: URL(string: streamed)!, purpose: .image, limit: 10_000))
        }
    }

    /// A GIF's download stops once its first frame is in.
    @Test func aGifDownloadStopsAtItsFirstFrame() async throws {
        let gif = TestImages.gif(width: 300, height: 200, frames: [.red, .blue, .green, .red])
        let url = "https://images.exemple.fr/anime.gif"
        let size = 256
        RecordedAnswers.serve(url, headers: ["Content-Type": "image/gif"],
                              chunks: stride(from: 0, to: gif.count, by: size).map { gif[$0..<min(gif.count, $0 + size)] }, paced: true)
        let response = try await http.get(InspirationRequest(url: URL(string: url)!, purpose: .image, limit: 1_000_000,
                                                             isEnough: GIFData.firstFrameIsComplete))
        #expect(response.truncated && response.body.count < gif.count && GIFData.firstFrameIsComplete(response.body))
        // The rest is never asked for.
        try await Task.sleep(for: .milliseconds(50))
        #expect(RecordedAnswers.stoppedEarly.contains(url))
    }

    /// A browser's name, no cookie sent back even when a site sets one; never a private address.
    @Test func noCookieAndABrowsersName() async throws {
        let url = "https://cookie.exemple.fr/"
        RecordedAnswers.serve(url, headers: ["Set-Cookie": "suivi=1; Path=/; Domain=cookie.exemple.fr"], chunks: [Data("ok".utf8)])
        _ = try await http.get(InspirationRequest(url: URL(string: url)!, purpose: .page, limit: 1000))
        _ = try await http.get(InspirationRequest(url: URL(string: url)!, purpose: .page, limit: 1000))
        let requests = RecordedAnswers.requestsTo(url)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
        // Safari's name, never Chrome's: macOS's network looks like Safari, and Awwwards refuses a Chrome name on it (16/11).
        #expect(requests.allSatisfy { agent in
            let name = agent.value(forHTTPHeaderField: "User-Agent") ?? ""
            return name.contains("Version/18.0 Safari/605.1.15") && !name.contains("Chrome")
        })
        await #expect(throws: InspirationFetchError.refusedAddress) {
            try await http.get(InspirationRequest(url: URL(string: "http://192.168.1.1/")!, purpose: .page, limit: 1000))
        }
        // An http address is read over https.
        RecordedAnswers.serve("https://ancien.exemple.fr/", chunks: [Data("ok".utf8)])
        let upgraded = try await http.get(InspirationRequest(url: URL(string: "http://ancien.exemple.fr/")!, purpose: .page, limit: 1000))
        #expect(upgraded.url.absoluteString == "https://ancien.exemple.fr/" && upgraded.text == "ok")
    }
}
