//
//  ProjectCardPresentationTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct ProjectCardPresentationTests {
    @Test func updatedTextUsesRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(
            ProjectCardPresentation.updatedText(
                updatedAt: now.addingTimeInterval(-30),
                now: now,
                locale: Locale(identifier: "en_US")
            ) == "Updated just now"
        )
        #expect(
            ProjectCardPresentation.updatedText(
                updatedAt: now.addingTimeInterval(-86_400),
                now: now,
                locale: Locale(identifier: "en_US")
            ) == "Updated 1 day ago"
        )
    }

    @Test func timelineStartsAtFutureTimestampThenUsesPastOffset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = now.addingTimeInterval(30)

        #expect(
            ProjectCardPresentation.timelineStartDate(updatedAt: updatedAt, now: now)
                == updatedAt
        )
        #expect(
            ProjectCardPresentation.timelineStartDate(updatedAt: updatedAt, now: updatedAt)
                == updatedAt.addingTimeInterval(60)
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
