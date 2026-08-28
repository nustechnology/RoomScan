//
//  ProjectCardPresentationTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import SwiftUI
import Testing

struct ProjectCardPresentationTests {
    @Test func updatedTextUsesMonthDayFormatForCurrentYear() {
        let now = Date(timeIntervalSince1970: 1_781_251_200) // Jun 12, 2026 UTC

        #expect(
            ProjectCardPresentation.updatedText(
                updatedAt: now,
                now: now,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ) == "Jun 12"
        )
    }

    @Test func updatedTextIncludesYearWhenNotInCurrentYear() {
        let now = Date(timeIntervalSince1970: 1_781_251_200) // Jun 12, 2026 UTC

        #expect(
            ProjectCardPresentation.updatedText(
                updatedAt: Date(timeIntervalSince1970: 1_718_208_000), // Jun 12, 2024 UTC
                now: now,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ) == "Jun 12, 2024"
        )
    }

    @Test func updatedTextKeepsMonthDayOrderForBritishEnglish() {
        let now = Date(timeIntervalSince1970: 1_781_251_200) // Jun 12, 2026 UTC

        #expect(
            ProjectCardPresentation.updatedText(
                updatedAt: now,
                now: now,
                locale: Locale(identifier: "en_GB"),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ) == "Jun 12"
        )
    }

    @Test func updatedTextIncludesYearWhenDisplayTimeZoneIsPreviousYear() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let pacific = TimeZone(identifier: "America/Los_Angeles")!

        let now = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 10))!
        let updatedAt = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 4))!

        #expect(
            ProjectCardPresentation.updatedText(
                updatedAt: updatedAt,
                now: now,
                calendar: utcCalendar,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: pacific
            ) == "Dec 31, 2025"
        )
    }

    @Test func updatedTextOmitsYearWhenDisplayTimeZoneStaysInCurrentYear() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let pacific = TimeZone(identifier: "America/Los_Angeles")!

        let now = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 10))!
        let updatedAt = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 10))!

        #expect(
            ProjectCardPresentation.updatedText(
                updatedAt: updatedAt,
                now: now,
                calendar: utcCalendar,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: pacific
            ) == "Jan 2"
        )
    }

    @Test func yearBoundaryIsStartOfNextCalendarYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 15))!

        #expect(
            YearBoundaryTimelineSchedule.nextBoundary(after: start, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
    }

    @Test func yearBoundaryEntriesStartNowThenAdvanceEachNewYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 15))!
        var entries = YearBoundaryTimelineSchedule(calendar: calendar)
            .entries(from: start, mode: .normal)
        let first = entries.next()
        let second = entries.next()
        let third = entries.next()

        #expect(first == start)
        #expect(second == calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        #expect(third == calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
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
