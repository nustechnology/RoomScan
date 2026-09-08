//
//  ScanFlowCoordinatorTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct ScanFlowCoordinatorTests {
    @Test func initialStep_withNilRecoveredDraft_returnsReadiness() {
        let step = ScanFlowStep.initialStep(for: nil)
        #expect(step == .readiness)
    }

    @Test func initialStep_bypassingReadiness_returnsCamera() {
        let step = ScanFlowStep.initialStep(for: nil, bypassingReadiness: true)
        #expect(step == .camera)
    }

    @Test func initialStep_withRecoveredDraft_returnsReviewWithDraft() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let meshURL = tempDir.appendingPathComponent("mesh.usdz")
        let thumbnailURL = tempDir.appendingPathComponent("thumbnail.jpg")

        let draft = RoomScanDraft(
            id: "draft-123",
            createdAt: Date(),
            meshFileURL: meshURL,
            thumbnailFileURL: thumbnailURL,
            name: "Recovered Scan",
            projectID: "project-abc"
        )

        let step = ScanFlowStep.initialStep(for: draft)
        #expect(step == .review(draft))
    }
}
