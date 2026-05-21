import Foundation

enum PollerState {
    case idle
    case downloading
    case done
}

class Poller {
    private let client: APIClient
    private let savePath: String
    private let onStateChange: (PollerState) -> Void
    private var timer: Timer?

    init(client: APIClient, savePath: String, onStateChange: @escaping (PollerState) -> Void) {
        self.client = client
        self.savePath = savePath
        self.onStateChange = onStateChange
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        Task {
            do {
                let articles = try await client.fetchArticles()
                guard !articles.isEmpty else { return }

                onStateChange(.downloading)
                await downloadAll(articles)
                onStateChange(.done)
            } catch {
                print("[Poller] error: \(error)")
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
                    } catch {
                        print("[Poller] failed article \(article.id): \(error)")
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
}
