//
//  ProjectDetailViewTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct ProjectDetailViewTests {
    @Test func createdDateTextUsesAbbreviatedMonthDayAndYear() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)

        #expect(
            ProjectDetailPresentation.createdDateText(
                for: date,
                locale: Locale(identifier: "en_US_POSIX")
            ) == "Jun 15, 2025"
        )
    }

    @Test func sharedUserCountTextDisplaysPeopleCount() {
        #expect(ProjectDetailPresentation.sharedUserCountText(for: 0) == "0 people")
        #expect(ProjectDetailPresentation.sharedUserCountText(for: 1) == "1 person")
        #expect(ProjectDetailPresentation.sharedUserCountText(for: 2) == "2 people")
    }

    @Test func scansTitleDisplaysCurrentScanCount() {
        #expect(ProjectDetailPresentation.scansTitle(for: 0) == "Scans (0)")
        #expect(ProjectDetailPresentation.scansTitle(for: 4) == "Scans (4)")
    }

    @Test func showsOwnerActionsOnlyForEditableAccessPolicy() {
        #expect(ProjectDetailPresentation.showsOwnerActions(for: .editable))
        #expect(ProjectDetailPresentation.showsOwnerActions(for: .readOnly) == false)
        #expect(DetailAccessPolicy.editable.allowsOwnerActions)
        #expect(DetailAccessPolicy.readOnly.allowsOwnerActions == false)
    }
}
