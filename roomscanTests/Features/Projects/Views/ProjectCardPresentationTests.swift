//
//  ProjectCardPresentationTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct ProjectCardPresentationTests {
    @Test func scanCountTextUsesRemoteTotalWhenFullyLoaded() {
        #expect(
            ProjectCardPresentation.scanCountText(remoteScanCount: 10, loadedScanCount: 10)
                == "10 room scans"
        )
        #expect(
            ProjectCardPresentation.scanCountText(remoteScanCount: 0, loadedScanCount: 0)
                == "0 room scans"
        )
    }

    @Test func scanCountTextCallsOutPartialLocalCache() {
        #expect(
            ProjectCardPresentation.scanCountText(remoteScanCount: 10, loadedScanCount: 4)
                == "10 room scans · 4 loaded"
        )
    }

    @Test func showMoreTitleUsesLoadedWordingWhenCacheIsIncomplete() {
        #expect(
            ProjectCardPresentation.showMoreTitle(remainingLoadedCount: 1, hasIncompleteLocalCache: true)
                == "Show 1 more loaded scans"
        )
        #expect(
            ProjectCardPresentation.showMoreTitle(remainingLoadedCount: 1, hasIncompleteLocalCache: false)
                == "Show 1 more room scans"
        )
    }
}
