import Foundation

public struct Article: Codable, Equatable {
    public let id: Int
    public let title: String
    public let domain: String

    public init(id: Int, title: String, domain: String) {
        self.id = id
        self.title = title
        self.domain = domain
    }
}

public protocol CompanionAPIClient {
    func fetchArticles() async throws -> [Article]
    func fetchMarkdown(articleID: Int) async throws -> String
    func markDownloaded(articleID: Int) async throws
}

public protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

public protocol SleepProviding {
    func sleep(seconds: Double) async throws
}

public struct TaskSleeper: SleepProviding {
    public init() {}

    public func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

public enum APIClientError: Error, Equatable {
    case invalidMarkdownData
    case maxRetriesExceeded
}

public enum AuthAPIClientError: Error, Equatable {
    case invalidEmail
    case invalidOTP
    case rateLimited
    case timeout
    case network
    case serverError(message: String)
    case invalidResponse
}

public final class APIClient: CompanionAPIClient {
    private let baseURL: String
    private let email: String
    private let token: String
    private let transport: any HTTPTransport
    private let sleeper: any SleepProviding
    private let maxRetries: Int

    public init(
        baseURL: String,
        email: String,
        token: String,
        transport: (any HTTPTransport)? = nil,
        sleeper: any SleepProviding = TaskSleeper(),
        maxRetries: Int = 5
    ) {
        self.baseURL = baseURL
        self.email = email
        self.token = token
        self.transport = transport ?? URLSession(configuration: .default)
        self.sleeper = sleeper
        self.maxRetries = maxRetries
    }

    public func fetchArticles() async throws -> [Article] {
        let url = try makeURL("/api/companion/articles")
        let request = makeRequest(url: url)
        let (data, _) = try await perform(request)
        return try JSONDecoder().decode([Article].self, from: data)
    }

    public func fetchMarkdown(articleID: Int) async throws -> String {
        let url = try makeURL("/api/companion/articles/\(articleID)/markdown")
        let request = makeRequest(url: url)
        let (data, _) = try await perform(request)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw APIClientError.invalidMarkdownData
        }
        return markdown
    }

    public func markDownloaded(articleID: Int) async throws {
        let url = try makeURL("/api/companion/articles/\(articleID)/downloaded")
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        _ = try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var delay: Double = 1.0
        for attempt in 0...maxRetries {
            let (data, response) = try await transport.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                if attempt == maxRetries {
                    throw APIClientError.maxRetriesExceeded
                }

                try await sleeper.sleep(seconds: delay)
                delay = min(delay * 2, 60)
                continue
            }
            return (data, response)
        }

        throw APIClientError.maxRetriesExceeded
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

public protocol CompanionAuthClient {
    func requestSignInOTP(email: String) async throws
    func verifySignInOTP(email: String, otp: String) async throws -> String
}

public final class AuthAPIClient: CompanionAuthClient {
    private let baseURL: String
    private let transport: any HTTPTransport

    public init(baseURL: String, transport: (any HTTPTransport)? = nil) {
        self.baseURL = baseURL
        if let transport {
            self.transport = transport
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            self.transport = URLSession(configuration: config)
        }
    }

    public func requestSignInOTP(email: String) async throws {
        let url = try makeURL("/api/sign_in")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SignInEmailRequest(email: email))

        let (data, http) = try await perform(request)

        switch http.statusCode {
        case 200...299:
            return
        case 422:
            throw AuthAPIClientError.invalidEmail
        case 429:
            throw AuthAPIClientError.rateLimited
        case 500...599:
            throw AuthAPIClientError.serverError(message: "Server error. Please try again in a moment.")
        default:
            let message = errorMessage(from: data) ?? "Could not send OTP. Please try again."
            throw AuthAPIClientError.serverError(message: message)
        }
    }

    public func verifySignInOTP(email: String, otp: String) async throws -> String {
        let url = try makeURL("/api/sign_in/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SignInVerifyRequest(email: email, otp: otp))

        let (data, http) = try await perform(request)

        switch http.statusCode {
        case 200...299:
            let payload = try JSONDecoder().decode(SignInVerifyResponse.self, from: data)
            guard !payload.token.isEmpty else {
                throw AuthAPIClientError.invalidResponse
            }
            return payload.token
        case 401:
            throw AuthAPIClientError.invalidOTP
        case 429:
            throw AuthAPIClientError.rateLimited
        case 500...599:
            throw AuthAPIClientError.serverError(message: "Server error. Please try again in a moment.")
        default:
            let message = errorMessage(from: data) ?? "Could not verify OTP. Please try again."
            throw AuthAPIClientError.serverError(message: message)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await transport.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AuthAPIClientError.invalidResponse
            }
            return (data, http)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw AuthAPIClientError.timeout
            }
            throw AuthAPIClientError.network
        } catch let error as AuthAPIClientError {
            throw error
        } catch {
            throw AuthAPIClientError.network
        }
    }

    private func makeURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }
        return url
    }

    private func errorMessage(from data: Data) -> String? {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data),
            let dict = raw as? [String: Any]
        else {
            return nil
        }

        if let error = dict["error"] as? String, !error.isEmpty {
            return error.replacingOccurrences(of: "_", with: " ").capitalized
        }

        if
            let errors = dict["errors"] as? [String],
            let firstError = errors.first,
            !firstError.isEmpty
        {
            return firstError
        }

        return nil
    }
}

private struct SignInEmailRequest: Encodable {
    let email: String
}

private struct SignInVerifyRequest: Encodable {
    let email: String
    let otp: String
}

private struct SignInVerifyResponse: Decodable {
    let token: String
}
