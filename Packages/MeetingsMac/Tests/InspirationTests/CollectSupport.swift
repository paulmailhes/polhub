import Foundation
import Persistence
@testable import Inspiration

/// The web as the collection tests see it: recorded, invented pages and images drawn by the tests, served by
/// address. Nothing goes on the network; an address not served answers as an unreachable host.
final class FakeHTTP: InspirationHTTP, @unchecked Sendable {
    struct Answer {
        var status: Int
        var body: Data
        var contentType: String?
        var finalURL: URL?
    }

    private let lock = NSLock()
    private var answers: [String: Answer] = [:]
    private var failures: [String: any Error] = [:]
    private var log: [String] = []
    private var stopped: [String: Int] = [:]
    /// How long each answer takes (set before use).
    var delay: Duration = .zero

    /// Every address asked, in order.
    var requested: [String] { lock.withLock { log } }

    /// The bytes an image's download stopped at, when it stopped early.
    func stoppedAt(_ url: String) -> Int? { lock.withLock { stopped[url] } }

    func page(_ url: String, fixture: String, status: Int = 200, finalURL: String? = nil) {
        page(url, html: CollectFixtures.html(fixture), status: status, finalURL: finalURL)
    }

    func page(_ url: String, html: String, status: Int = 200, finalURL: String? = nil) {
        lock.withLock {
            answers[url] = Answer(status: status, body: Data(html.utf8), contentType: "text/html", finalURL: finalURL.flatMap(URL.init(string:)))
        }
    }

    func image(_ url: String, _ data: Data, contentType: String = "image/jpeg", status: Int = 200) {
        lock.withLock { answers[url] = Answer(status: status, body: data, contentType: contentType) }
    }

    func fail(_ url: String, _ error: any Error) {
        lock.withLock { failures[url] = error }
    }

    func get(_ request: InspirationRequest) async throws -> InspirationResponse {
        let address = request.url.absoluteString
        let (answer, failure): (Answer?, (any Error)?) = lock.withLock {
            log.append(address)
            return (answers[address], failures[address])
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        guard PublicWeb.isAllowed(request.url) else { throw InspirationFetchError.refusedAddress }
        guard let answer else { throw URLError(.cannotConnectToHost) }
        var body = answer.body
        var truncated = false
        switch request.purpose {
        case .image where body.count > request.limit:
            throw InspirationFetchError.tooLarge
        case .page where body.count > request.limit:
            body = body.prefix(request.limit)
            truncated = true
        default:
            break
        }
        // As the live loader: chunk by chunk, stopped once enough came.
        if let isEnough = request.isEnough {
            var length = 0
            while length < body.count {
                length = min(body.count, length + 512)
                if length < body.count, isEnough(body.prefix(length)) {
                    body = body.prefix(length)
                    truncated = true
                    let stoppedAt = length
                    lock.withLock { stopped[address] = stoppedAt }
                    break
                }
            }
        }
        return InspirationResponse(url: answer.finalURL ?? request.url, status: answer.status, contentType: answer.contentType,
                                   body: body, truncated: truncated)
    }
}

/// The fake web, its line dropping while images come down (the Wi-Fi goes, the Mac falls asleep): the first
/// `imagesBeforeDrop` images come, then nothing comes, page nor image, until `reconnect()` (audit of 19/11).
/// `FakeHTTP.fail` keeps a failure for good: this one cuts the line, then gives it back.
final class DroppingLine: InspirationHTTP, @unchecked Sendable {
    let web: FakeHTTP
    private let lock = NSLock()
    private var imagesBeforeDrop: Int
    private var down = false

    init(_ web: FakeHTTP, imagesBeforeDrop: Int) {
        self.web = web
        self.imagesBeforeDrop = imagesBeforeDrop
    }

    func reconnect() {
        lock.withLock {
            down = false
            imagesBeforeDrop = .max
        }
    }

    func get(_ request: InspirationRequest) async throws -> InspirationResponse {
        let lineIsUp: Bool = lock.withLock {
            if !down, request.purpose == .image {
                if imagesBeforeDrop == 0 { down = true } else { imagesBeforeDrop -= 1 }
            }
            return !down
        }
        guard lineIsUp else { throw URLError(.networkConnectionLost) }
        return try await web.get(request)
    }
}

/// Quick Look as the tests see it: a drawn image for any file, or nothing.
struct FakeThumbnailer: MockupThumbnailing {
    var image: Data? = TestImages.png(width: 2400, height: 1800)

    func thumbnail(of file: URL, maxSide: Int) async throws -> Data {
        guard let image else { throw ImageShrinkError.notAnImage }
        return image
    }
}

/// The pauses between LinkedIn calls, counted instead of waited.
final class PauseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var pauses: [Duration] = []
    var count: Int { lock.withLock { pauses.count } }
    var all: [Duration] { lock.withLock { pauses } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in lock.withLock { pauses.append(duration) } }
    }
}

enum CollectFixtures {
    static var folder: URL {
        let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures", directoryHint: .isDirectory)
        return fixtures.appending(path: "collecte", directoryHint: .isDirectory)
    }

    static func html(_ name: String) -> String {
        (try? String(contentsOf: folder.appending(path: name), encoding: .utf8)) ?? ""
    }

    // The invented addresses of the fixtures.
    static let lumiere = "https://lumiere.exemple.fr/?ref=awwwards"
    static let lumiereImage = "https://lumiere.exemple.fr/images/partage.jpg"
    static let awwwardsThumbnail = "https://assets.awwwards.com/awards/submissions/2026/11/lumiere-exemple-capture.jpg?w=1600&q=80"
    static let studioPage = "https://www.linkedin.com/company/studio-exemple/"
    static let atelierPage = "https://www.linkedin.com/company/atelier-nord/"
    static let cafeUrn = "7528000153191634567"
    static let knownUrn = "7527800084890834567"
    static let marqueUrn = "7527280410625234567"

    static func embed(_ urn: String) -> String { "https://www.linkedin.com/embed/feed/update/urn:li:activity:\(urn)" }

    static func media(_ id: String, _ variant: String, _ token: String) -> String {
        "https://media.licdn.com/dms/image/v2/\(id)/\(variant)/\(variant)/0/1763279100000?e=1765411200&v=beta&t=\(token)"
    }
}

/// An empty hub (base in memory, image folders in a temporary folder) and its collector on the fake web.
struct CollectWorld {
    let root: URL
    let paths: AppPaths
    let database: AppDatabase
    let http = FakeHTTP()
    let pauses = PauseCounter()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "collecte \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = AppPaths(root: root.appending(path: "hub", directoryHint: .isDirectory), logs: root.appending(path: "Logs"))
        database = try AppDatabase.inMemory()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    var store: InspirationStore { InspirationStore(database) }

    /// `http`: another way to the fake web (a `DroppingLine`), else the fake web itself.
    func collector(http: (any InspirationHTTP)? = nil, thumbnailer: any MockupThumbnailing = FakeThumbnailer(),
                   runLog: CollectionRunLog? = nil, configuration: InspirationCollector.Configuration = .init()) -> InspirationCollector {
        InspirationCollector(database: database, paths: paths, http: http ?? self.http, thumbnailer: thumbnailer, runLog: runLog,
                             configuration: configuration, sleep: pauses.sleep)
    }

    func imageURL(_ kind: InspirationKind, _ name: String) -> URL {
        paths.inspirationImages(kind).appending(path: name)
    }

    /// The files of a kind's image folder, hidden ones included.
    func imageFiles(_ kind: InspirationKind) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: paths.inspirationImages(kind).path(percentEncoded: false))) ?? []).sorted()
    }

    /// A fresh, private preferences domain.
    static func runLog() -> CollectionRunLog {
        let name = "polhub.tests.collecte.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return CollectionRunLog(defaults: defaults)
    }
}
