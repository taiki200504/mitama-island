import Testing
@testable import OpenIslandApp

/// The island must not fold itself away while a file is on its way down to it.
@MainActor
struct ShelfDragHoldTests {
    @Test
    func aNoticeExpiringDoesNotCloseTheIslandUnderACarriedFile() {
        let model = AppModel()
        model.carriedFileDragProbe = { true }

        model.present(notice: "聞いています")
        #expect(model.notchStatus == .opened)

        model.clearNotice()

        // The words go; the landing place stays.
        #expect(model.notice == nil)
        #expect(model.notchStatus == .opened)
    }

    @Test
    func aNoticeExpiringClosesTheIslandWhenNothingIsBeingCarried() {
        let model = AppModel()
        model.carriedFileDragProbe = { false }

        model.present(notice: "聞いています")
        #expect(model.notchStatus == .opened)

        model.clearNotice()

        #expect(model.notchStatus == .closed)
    }

    @Test
    func theIslandFoldsAwayOnceTheFileHasLanded() async throws {
        let model = AppModel()
        nonisolated(unsafe) var carrying = true
        model.carriedFileDragProbe = { carrying }

        model.present(notice: "聞いています")
        model.clearNotice()
        #expect(model.notchStatus == .opened)

        carrying = false
        try await Task.sleep(for: .seconds(AppModel.noticeCloseRetryDelay + 0.3))

        #expect(model.notchStatus == .closed)
    }

    @Test
    func aCarriedFileDefersTheTimedNotificationCollapse() {
        let model = AppModel()
        model.notchStatus = .opened
        model.carriedFileDragProbe = { true }

        #expect(model.shouldDeferTimedNotificationAutoCollapse)

        model.carriedFileDragProbe = { false }
        #expect(!model.shouldDeferTimedNotificationAutoCollapse)
    }
}
