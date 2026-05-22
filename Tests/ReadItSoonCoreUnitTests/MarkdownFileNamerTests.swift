import Testing
@testable import ReadItSoonCore

struct MarkdownFileNamerTests {
    @Test
    func sanitizeTitleWithASCII() {
        #expect(MarkdownFileNamer.sanitizeTitle("Hello, World!") == "hello-world")
    }

    @Test
    func sanitizeTitleWithNonASCII() {
        #expect(MarkdownFileNamer.sanitizeTitle("Café 漢字") == "caf-")
    }

    @Test
    func sanitizeTitleWithOnlySymbolsFallsBackToUntitled() {
        #expect(MarkdownFileNamer.sanitizeTitle("!!!") == "untitled")
        #expect(MarkdownFileNamer.sanitizeTitle("") == "untitled")
    }

    @Test
    func uniquePathAddsNumericSuffix() {
        let fileSystem = MockFileSystem(existingPaths: [
            "/tmp/posts/my-title.md",
            "/tmp/posts/my-title-2.md"
        ])

        let path = MarkdownFileNamer.uniquePath(
            directory: "/tmp/posts",
            title: "my-title",
            fileSystem: fileSystem
        )

        #expect(path == "/tmp/posts/my-title-3.md")
    }
}

private struct MockFileSystem: FileSystemManaging {
    let existingPaths: Set<String>

    func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws {}

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func write(_ content: String, toFile path: String) throws {}
}
