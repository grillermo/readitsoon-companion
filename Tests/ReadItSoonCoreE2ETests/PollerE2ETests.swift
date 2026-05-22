import Foundation
import Testing
@testable import ReadItSoonCore

struct PollerE2ETests {
    @Test
    func pollerEndToEndAgainstLocalBackendProcess() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let downloadsDirectory = tempDirectory.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        let stateFile = tempDirectory.appendingPathComponent("state.json")
        try "{\"downloaded\":[]}".write(to: stateFile, atomically: true, encoding: .utf8)

        let scriptURL = tempDirectory.appendingPathComponent("mock_server.py")
        try serverScript(stateFile: stateFile).write(to: scriptURL, atomically: true, encoding: .utf8)

        let port = Int.random(in: 20_000...40_000)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path, "\(port)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        try await waitForServer(baseURL: "http://127.0.0.1:\(port)")

        let client = APIClient(
            baseURL: "http://127.0.0.1:\(port)",
            email: "user@example.com",
            token: "token",
            transport: URLSession(configuration: .default),
            sleeper: NoopSleeper()
        )

        let poller = Poller(
            client: client,
            savePath: downloadsDirectory.path,
            scheduler: noOpScheduler,
            onUpdate: { _ in }
        )

        await poller.pollNow()

        let outputPath = downloadsDirectory.appendingPathComponent("e2e-article.md")
        #expect(try String(contentsOf: outputPath) == "# E2E")

        let stateData = try Data(contentsOf: stateFile)
        let state = try JSONDecoder().decode(MockState.self, from: stateData)
        #expect(state.downloaded == [101])
    }

    private func waitForServer(baseURL: String) async throws {
        let healthURL = URL(string: "\(baseURL)/api/companion/articles?email=probe@example.com")!

        for _ in 0..<40 {
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    return
                }
            } catch {
                // Keep polling until the process is ready.
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw URLError(.cannotConnectToHost)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func noOpScheduler(_: TimeInterval, _: @escaping () -> Void) -> PollerSchedulingToken {
        DummyScheduleToken()
    }

    private func serverScript(stateFile: URL) -> String {
        """
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

PORT = int(sys.argv[1])
STATE_FILE = r\"\(stateFile.path)\"

state = {"downloaded": []}

class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, status, body):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/companion/articles":
            self._json(200, [{"id": 101, "title": "E2E Article", "domain": "example.com"}])
            return

        if path == "/api/companion/articles/101/markdown":
            self._text(200, "# E2E")
            return

        self._json(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/companion/articles/101/downloaded":
            state["downloaded"].append(101)
            with open(STATE_FILE, "w", encoding="utf-8") as fh:
                json.dump(state, fh)
            self._json(200, {"ok": True})
            return

        self._json(404, {"error": "not found"})

httpd = HTTPServer(("127.0.0.1", PORT), Handler)
httpd.serve_forever()
"""
    }
}

private struct MockState: Decodable {
    let downloaded: [Int]
}

private final class DummyScheduleToken: PollerSchedulingToken {
    func invalidate() {}
}

private struct NoopSleeper: SleepProviding {
    func sleep(seconds: Double) async throws {}
}
