import Foundation
import Testing
@testable import ReadItSoonCore

struct APIClientRetryTests {
    @Test
    func fetchArticlesRetriesOn429ThenSucceeds() async throws {
        let transport = SequenceTransport(responses: [
            .status(429, body: ""),
            .status(429, body: ""),
            .status(200, body: "[{\"id\":1,\"title\":\"A\",\"domain\":\"example.com\"}]")
        ])
        let sleeper = RecordingSleeper()

        let client = APIClient(
            baseURL: "https://example.com",
            email: "user@example.com",
            token: "abc",
            transport: transport,
            sleeper: sleeper,
            maxRetries: 5
        )

        let articles = try await client.fetchArticles()

        #expect(articles.count == 1)
        #expect(transport.requestCount == 3)
        #expect(sleeper.delays == [1.0, 2.0])
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(transport.requests.first?.url?.query == "email=user@example.com")
    }

    @Test
    func fetchArticlesFailsAfterMaxRetries() async {
        let transport = SequenceTransport(responses: [
            .status(429, body: ""),
            .status(429, body: ""),
            .status(429, body: "")
        ])
        let sleeper = RecordingSleeper()

        let client = APIClient(
            baseURL: "https://example.com",
            email: "user@example.com",
            token: "abc",
            transport: transport,
            sleeper: sleeper,
            maxRetries: 2
        )

        do {
            _ = try await client.fetchArticles()
            Issue.record("Expected max retry error")
        } catch let error as APIClientError {
            #expect(error == .maxRetriesExceeded)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(transport.requestCount == 3)
        #expect(sleeper.delays == [1.0, 2.0])
    }
}

private final class SequenceTransport: HTTPTransport {
    enum Response {
        case status(Int, body: String)
    }

    private(set) var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    var requestCount: Int {
        requests.count
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let response = responses.removeFirst()
        switch response {
        case let .status(statusCode, body):
            let url = request.url ?? URL(string: "https://example.com")!
            let http = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), http)
        }
    }
}

private final class RecordingSleeper: SleepProviding {
    private(set) var delays: [Double] = []

    func sleep(seconds: Double) async throws {
        delays.append(seconds)
    }
}
