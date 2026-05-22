import Foundation
import Testing
@testable import ReadItSoonCore

struct ConfigTests {
    @Test
    func saveAndLoadRoundTrip() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("config.json")
        let original = Config(savePath: "/tmp/articles")

        Config.save(original, to: configURL)
        let loaded = Config.load(from: configURL)

        #expect(loaded == original)
    }

    @Test
    func loadReturnsNilWhenFileMissing() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("missing.json")
        #expect(Config.load(from: configURL) == nil)
    }

    @Test
    func loadReturnsNilWhenFileCorrupt() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("corrupt.json")
        try "{invalid-json".write(to: configURL, atomically: true, encoding: .utf8)

        #expect(Config.load(from: configURL) == nil)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
