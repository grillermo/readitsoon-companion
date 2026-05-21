import Foundation

struct Article: Codable {
    let id: Int
    let title: String
    let domain: String
}

class APIClient {
    private let baseURL: String
    private let email: String
    private let token: String
    private let session = URLSession(configuration: .default)

    init(baseURL: String, email: String, token: String) {
        self.baseURL = baseURL
        self.email = email
        self.token = token
    }

    func fetchArticles() async throws -> [Article] {
        let url = try makeURL("/api/companion/articles")
        let request = makeRequest(url: url)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([Article].self, from: data)
    }

    func fetchMarkdown(articleID: Int) async throws -> String {
        let url = try makeURL("/api/companion/articles/\(articleID)/markdown")
        let request = makeRequest(url: url)
        let (data, _) = try await session.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func markDownloaded(articleID: Int) async throws {
        let url = try makeURL("/api/companion/articles/\(articleID)/downloaded")
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        _ = try await session.data(for: request)
    }

    private func makeURL(_ path: String) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "email", value: email)]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
