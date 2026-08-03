//
//  SharedCardPresentationTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct SharedCardPresentationTests {
    @Test func projectSubtitleUsesSingularForOneScan() {
        #expect(SharedProjectCardPresentation.subtitle(ownerName: "A", scanCount: 0) == "Owner: A · 0 scans")
        #expect(SharedProjectCardPresentation.subtitle(ownerName: "A", scanCount: 1) == "Owner: A · 1 scan")
        #expect(SharedProjectCardPresentation.subtitle(ownerName: "A", scanCount: 2) == "Owner: A · 2 scans")
    }

    @Test func scanOwnerLineUsesSingularForOneNote() {
        #expect(SharedScanCardPresentation.ownerLine(ownerName: "B", noteCount: 0) == "Owner: B · 0 notes")
        #expect(SharedScanCardPresentation.ownerLine(ownerName: "B", noteCount: 1) == "Owner: B · 1 note")
        #expect(SharedScanCardPresentation.ownerLine(ownerName: "B", noteCount: 2) == "Owner: B · 2 notes")
    }
}
