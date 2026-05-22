import Foundation

public enum PollerState: Equatable {
    case idle
    case downloading
    case done
    case error
}

public struct PollerUpdate: Equatable {
    public let state: PollerState
    public let pendingTitles: [String]
    public let lastDownloadedTitle: String?

    public init(state: PollerState, pendingTitles: [String], lastDownloadedTitle: String?) {
        self.state = state
        self.pendingTitles = pendingTitles
        self.lastDownloadedTitle = lastDownloadedTitle
    }
}

public protocol FileSystemManaging {
    func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws
    func fileExists(atPath path: String) -> Bool
    func write(_ content: String, toFile path: String) throws
}

public struct LocalFileSystem: FileSystemManaging {
    public init() {}

    public func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: withIntermediateDirectories)
    }

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func write(_ content: String, toFile path: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

public struct MarkdownFileNamer {
    public static func sanitizeTitle(_ title: String) -> String {
        var slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
        slug = slug.unicodeScalars
            .filter { $0.value < 128 }
            .map { Character($0) }
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .map { String($0) }
            .joined()

        return slug.isEmpty ? "untitled" : slug
    }

    public static func uniquePath(
        directory: String,
        title: String,
        fileSystem: any FileSystemManaging
    ) -> String {
        let basePath = (directory as NSString).appendingPathComponent("\(title).md")
        guard fileSystem.fileExists(atPath: basePath) else { return basePath }

        var suffix = 2
        while true {
            let candidate = (directory as NSString).appendingPathComponent("\(title)-\(suffix).md")
            if !fileSystem.fileExists(atPath: candidate) {
                return candidate
            }
            suffix += 1
        }
    }
}

public protocol PollerSchedulingToken: AnyObject {
    func invalidate()
}

extension Timer: PollerSchedulingToken {}

public typealias PollerScheduler = (_ interval: TimeInterval, _ action: @escaping () -> Void) -> PollerSchedulingToken

public final class Poller {
    private let client: any CompanionAPIClient
    private let savePath: String
    private let onUpdate: (PollerUpdate) -> Void
    private let progress: PollerProgress
    private let fileSystem: any FileSystemManaging
    private let scheduler: PollerScheduler
    private let pollInterval: TimeInterval
    private let maxConcurrentDownloads: Int

    private var scheduleToken: PollerSchedulingToken?

    public init(
        client: any CompanionAPIClient,
        savePath: String,
        pollInterval: TimeInterval = 60,
        maxConcurrentDownloads: Int = 3,
        fileSystem: any FileSystemManaging = LocalFileSystem(),
        scheduler: @escaping PollerScheduler = Poller.defaultScheduler,
        onUpdate: @escaping (PollerUpdate) -> Void
    ) {
        self.client = client
        self.savePath = savePath
        self.pollInterval = pollInterval
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.fileSystem = fileSystem
        self.scheduler = scheduler
        self.onUpdate = onUpdate
        self.progress = PollerProgress()
    }

    deinit {
        scheduleToken?.invalidate()
    }

    public func start() {
        Task {
            await emitUpdate(state: .idle)
            await runPollCycle()
        }

        scheduleToken = scheduler(pollInterval) { [weak self] in
            self?.poll()
        }
    }

    public func pollNow() async {
        await runPollCycle()
    }

    public static func defaultScheduler(interval: TimeInterval, action: @escaping () -> Void) -> PollerSchedulingToken {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            action()
        }
    }

    private func poll() {
        Task {
            await runPollCycle()
        }
    }

    private func runPollCycle() async {
        do {
            let articles = try await client.fetchArticles()
            let titles = articles.map(\.title)
            await progress.setPending(titles)

            if articles.isEmpty {
                await emitUpdate(state: .idle)
                return
            }

            await emitUpdate(state: .downloading)
            await downloadAll(articles)
            await emitUpdate(state: .done)
        } catch {
            print("[Poller] error: \(error)")
            await emitUpdate(state: .error)
        }
    }

    private func downloadAll(_ articles: [Article]) async {
        let semaphore = AsyncSemaphore(value: maxConcurrentDownloads)

        await withTaskGroup(of: Void.self) { group in
            for article in articles {
                group.addTask {
                    await semaphore.wait()

                    do {
                        try await self.downloadArticle(article)
                        await self.updateAfterDownload(title: article.title)
                    } catch {
                        print("[Poller] failed article \(article.id): \(error)")
                        await self.updateAfterFailure(title: article.title)
                    }
                    await semaphore.signal()
                }
            }
        }
    }

    private func downloadArticle(_ article: Article) async throws {
        let markdown = try await client.fetchMarkdown(articleID: article.id)

        try fileSystem.createDirectory(atPath: savePath, withIntermediateDirectories: true)

        let title = MarkdownFileNamer.sanitizeTitle(article.title)
        let filePath = MarkdownFileNamer.uniquePath(
            directory: savePath,
            title: title,
            fileSystem: fileSystem
        )

        try fileSystem.write(markdown, toFile: filePath)
        try await client.markDownloaded(articleID: article.id)
    }

    private func updateAfterDownload(title: String) async {
        await progress.markDownloaded(title)
        await emitUpdate(state: .downloading)
    }

    private func updateAfterFailure(title: String) async {
        await progress.removePending(title)
        await emitUpdate(state: .downloading)
    }

    private func emitUpdate(state: PollerState) async {
        let snapshot = await progress.snapshot()
        let update = PollerUpdate(
            state: state,
            pendingTitles: snapshot.pendingTitles,
            lastDownloadedTitle: snapshot.lastDownloadedTitle
        )
        onUpdate(update)
    }
}

public actor PollerProgress {
    private var pendingTitles: [String] = []
    private var lastDownloadedTitle: String?

    public init() {}

    public func setPending(_ titles: [String]) {
        pendingTitles = titles
    }

    public func markDownloaded(_ title: String) {
        removeOnePending(title)
        lastDownloadedTitle = title
    }

    public func removePending(_ title: String) {
        removeOnePending(title)
    }

    public func snapshot() -> (pendingTitles: [String], lastDownloadedTitle: String?) {
        (pendingTitles, lastDownloadedTitle)
    }

    private func removeOnePending(_ title: String) {
        guard let index = pendingTitles.firstIndex(of: title) else { return }
        pendingTitles.remove(at: index)
    }
}
