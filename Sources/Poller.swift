import Foundation

enum PollerState {
    case idle
    case downloading
    case done
    case error
}

struct PollerUpdate {
    let state: PollerState
    let pendingTitles: [String]
    let lastDownloadedTitle: String?
}

class Poller {
    private let client: APIClient
    private let savePath: String
    private let onUpdate: (PollerUpdate) -> Void
    private var timer: Timer?
    private let progress = PollerProgress()

    init(client: APIClient, savePath: String, onUpdate: @escaping (PollerUpdate) -> Void) {
        self.client = client
        self.savePath = savePath
        self.onUpdate = onUpdate
    }

    func start() {
        Task { await emitUpdate(state: .idle) }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        Task {
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
    }

    private func downloadAll(_ articles: [Article]) async {
        let semaphore = AsyncSemaphore(value: 3)
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

        try FileManager.default.createDirectory(atPath: savePath, withIntermediateDirectories: true)

        let title = sanitize(article.title)
        let filePath = uniquePath(directory: savePath, title: title)
        try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)

        try await client.markDownloaded(articleID: article.id)
    }

    private func sanitize(_ title: String) -> String {
        var s = title.lowercased().replacingOccurrences(of: " ", with: "-")
        s = s.unicodeScalars
            .filter { $0.value < 128 }
            .map { Character($0) }
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .map { String($0) }
            .joined()
        return s.isEmpty ? "untitled" : s
    }

    private func uniquePath(directory: String, title: String) -> String {
        let base = (directory as NSString).appendingPathComponent("\(title).md")
        guard FileManager.default.fileExists(atPath: base) else { return base }
        var n = 2
        while true {
            let candidate = (directory as NSString).appendingPathComponent("\(title)-\(n).md")
            if !FileManager.default.fileExists(atPath: candidate) { return candidate }
            n += 1
        }
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

actor PollerProgress {
    private var pendingTitles: [String] = []
    private var lastDownloadedTitle: String?

    func setPending(_ titles: [String]) {
        pendingTitles = titles
    }

    func markDownloaded(_ title: String) {
        removeOnePending(title)
        lastDownloadedTitle = title
    }

    func removePending(_ title: String) {
        removeOnePending(title)
    }

    func snapshot() -> (pendingTitles: [String], lastDownloadedTitle: String?) {
        (pendingTitles, lastDownloadedTitle)
    }

    private func removeOnePending(_ title: String) {
        guard let index = pendingTitles.firstIndex(of: title) else { return }
        pendingTitles.remove(at: index)
    }
}
