import Testing
@testable import ReadItSoonCore

struct PollerProgressTests {
    @Test
    func markDownloadedRemovesPendingAndSetsLastDownloaded() async {
        let progress = PollerProgress()
        await progress.setPending(["A", "B", "C"])

        await progress.markDownloaded("B")
        let snapshot = await progress.snapshot()

        #expect(snapshot.pendingTitles == ["A", "C"])
        #expect(snapshot.lastDownloadedTitle == "B")
    }

    @Test
    func removePendingOnlyRemovesMatchingTitle() async {
        let progress = PollerProgress()
        await progress.setPending(["A", "B"])

        await progress.removePending("A")
        let snapshot = await progress.snapshot()

        #expect(snapshot.pendingTitles == ["B"])
        #expect(snapshot.lastDownloadedTitle == nil)
    }
}
