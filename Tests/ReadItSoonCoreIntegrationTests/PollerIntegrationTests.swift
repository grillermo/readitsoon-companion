import Foundation
import Testing
@testable import ReadItSoonCore

struct PollerIntegrationTests {
    @Test
    func pollWithEmptyListStaysIdle() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let transport = MockCompanionTransport(articles: [])
        let client = APIClient(
            baseURL: "https://example.com",
            email: "user@example.com",
            token: "token",
            transport: transport,
            sleeper: NoopSleeper()
        )

        let updates = UpdateCollector()
        let poller = Poller(
            client: client,
            savePath: tempDirectory.path,
            scheduler: noOpScheduler,
            onUpdate: { updates.append($0) }
        )

        await poller.pollNow()

        #expect(updates.last?.state == .idle)
        #expect(updates.last?.pendingTitles == [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).count == 0)
        #expect(await transport.downloadedIDs() == [])
    }

    @Test
    func pollWritesMarkdownAndMarksDownloaded() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let articles = [
            Article(id: 1, title: "First Post", domain: "a.com"),
            Article(id: 2, title: "Second Post", domain: "b.com")
        ]

        let transport = MockCompanionTransport(
            articles: articles,
            markdownByID: [
                1: "# First",
                2: "# Second"
            ]
        )

        let client = APIClient(
            baseURL: "https://example.com",
            email: "user@example.com",
            token: "token",
            transport: transport,
            sleeper: NoopSleeper()
        )

        let poller = Poller(
            client: client,
            savePath: tempDirectory.path,
            scheduler: noOpScheduler,
            onUpdate: { _ in }
        )

        await poller.pollNow()

        let firstPath = tempDirectory.appendingPathComponent("first-post.md")
        let secondPath = tempDirectory.appendingPathComponent("second-post.md")

        #expect(try String(contentsOf: firstPath) == "# First")
        #expect(try String(contentsOf: secondPath) == "# Second")
        #expect(await transport.downloadedIDs().sorted() == [1, 2])
    }

    @Test
    func pollContinuesWhenOneArticleFails() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let articles = [
            Article(id: 1, title: "Good", domain: "a.com"),
            Article(id: 2, title: "Bad", domain: "b.com")
        ]

        let transport = MockCompanionTransport(
            articles: articles,
            markdownByID: [1: "# Good"],
            failingMarkdownIDs: [2]
        )

        let client = APIClient(
            baseURL: "https://example.com",
            email: "user@example.com",
            token: "token",
            transport: transport,
            sleeper: NoopSleeper()
        )

        let updates = UpdateCollector()
        let poller = Poller(
            client: client,
            savePath: tempDirectory.path,
            scheduler: noOpScheduler,
            onUpdate: { updates.append($0) }
        )

        await poller.pollNow()

        let goodPath = tempDirectory.appendingPathComponent("good.md")
        #expect(try String(contentsOf: goodPath) == "# Good")
        #expect(await transport.downloadedIDs() == [1])
        #expect(updates.last?.state == .done)
    }

    @Test
    func pollRespectsConcurrencyCap() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let articles = (1...6).map { Article(id: $0, title: "Post \($0)", domain: "a.com") }
        let markdownByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, "# \($0.title)") })

        let transport = MockCompanionTransport(
            articles: articles,
            markdownByID: markdownByID,
            markdownDelayNanoseconds: 80_000_000
        )

        let client = APIClient(
            baseURL: "https://example.com",
            email: "user@example.com",
            token: "token",
            transport: transport,
            sleeper: NoopSleeper()
        )

        let poller = Poller(
            client: client,
            savePath: tempDirectory.path,
            maxConcurrentDownloads: 2,
            scheduler: noOpScheduler,
            onUpdate: { _ in }
        )

        await poller.pollNow()

        #expect(await transport.maxConcurrentMarkdownRequests() == 2)
    }

    @Test
    func updateCallbacksShrinkPendingTitles() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let articles = [
            Article(id: 1, title: "One", domain: "a.com"),
            Article(id: 2, title: "Two", domain: "a.com"),
            Article(id: 3, title: "Three", domain: "a.com")
        ]

        let markdownByID = [
            1: "# One",
            2: "# Two",
            3: "# Three"
        ]

        let transport = MockCompanionTransport(articles: articles, markdownByID: markdownByID)
        let client = APIClient(
            baseURL: "https://example.com",
            email: "user@example.com",
            token: "token",
            transport: transport,
            sleeper: NoopSleeper()
        )

        let updates = UpdateCollector()
        let poller = Poller(
            client: client,
            savePath: tempDirectory.path,
            scheduler: noOpScheduler,
            onUpdate: { updates.append($0) }
        )

        await poller.pollNow()

        let pendingCounts = updates.values
            .filter { $0.state == .downloading }
            .map { $0.pendingTitles.count }

        #expect(!pendingCounts.isEmpty)
        #expect(pendingCounts.first == 3)
        #expect(pendingCounts.last == 0)
        #expect(pendingCounts.sorted(by: >) == pendingCounts)
        #expect(updates.last?.state == .done)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func noOpScheduler(_: TimeInterval, _: @escaping () -> Void) -> PollerSchedulingToken {
        DummyScheduleToken()
    }
}

private final class DummyScheduleToken: PollerSchedulingToken {
    func invalidate() {}
}

private struct NoopSleeper: SleepProviding {
    func sleep(seconds: Double) async throws {}
}

private final class UpdateCollector {
    private let lock = NSLock()
    private var storage: [PollerUpdate] = []

    var values: [PollerUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var last: PollerUpdate? {
        lock.lock()
        defer { lock.unlock() }
        return storage.last
    }

    func append(_ value: PollerUpdate) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private actor MockCompanionTransport: HTTPTransport {
    private let articles: [Article]
    private let markdownByID: [Int: String]
    private let failingMarkdownIDs: Set<Int>
    private let markdownDelayNanoseconds: UInt64

    private var downloadedArticleIDs: [Int] = []
    private var inFlightMarkdownRequests: Int = 0
    private var maxInFlightMarkdownRequests: Int = 0

    init(
        articles: [Article],
        markdownByID: [Int: String] = [:],
        failingMarkdownIDs: Set<Int> = [],
        markdownDelayNanoseconds: UInt64 = 0
    ) {
        self.articles = articles
        self.markdownByID = markdownByID
        self.failingMarkdownIDs = failingMarkdownIDs
        self.markdownDelayNanoseconds = markdownDelayNanoseconds
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let pathComponents = url.pathComponents
        let method = request.httpMethod ?? "GET"

        if method == "GET", url.path == "/api/companion/articles" {
            let data = try JSONEncoder().encode(articles)
            return (data, httpResponse(statusCode: 200, url: url))
        }

        if method == "GET", pathComponents.count >= 6, pathComponents[3] == "articles", pathComponents[5] == "markdown" {
            guard let articleID = Int(pathComponents[4]) else {
                throw URLError(.badURL)
            }

            inFlightMarkdownRequests += 1
            maxInFlightMarkdownRequests = max(maxInFlightMarkdownRequests, inFlightMarkdownRequests)
            defer {
                inFlightMarkdownRequests -= 1
            }

            if markdownDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: markdownDelayNanoseconds)
            }

            if failingMarkdownIDs.contains(articleID) {
                throw URLError(.cannotLoadFromNetwork)
            }

            let markdown = markdownByID[articleID] ?? ""
            return (Data(markdown.utf8), httpResponse(statusCode: 200, url: url))
        }

        if method == "POST", pathComponents.count >= 6, pathComponents[3] == "articles", pathComponents[5] == "downloaded" {
            guard let articleID = Int(pathComponents[4]) else {
                throw URLError(.badURL)
            }
            downloadedArticleIDs.append(articleID)
            return (Data(), httpResponse(statusCode: 200, url: url))
        }

        throw URLError(.badServerResponse)
    }

    func downloadedIDs() -> [Int] {
        downloadedArticleIDs
    }

    func maxConcurrentMarkdownRequests() -> Int {
        maxInFlightMarkdownRequests
    }

    private func httpResponse(statusCode: Int, url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}
