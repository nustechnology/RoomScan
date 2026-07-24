//
//  MockProjectsServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct MockProjectsServiceTests {
    @Test func updateProjectMutatesStoredProject() async throws {
        let service = MockProjectsService(
            projects: [
                ProjectSummary(
                    id: "project-1",
                    name: "Original",
                    ownerName: "You",
                    createdAt: Date(timeIntervalSince1970: 900),
                    updatedAt: Date(timeIntervalSince1970: 1_000),
                    description: "Before",
                    sharedUserCount: 0,
                    roomScans: [
                        RoomScanSummary(
                            id: "scan-1",
                            name: "Living Room",
                            createdAt: Date(timeIntervalSince1970: 900),
                            thumbnailName: "thumbnail-0",
                            syncStatus: .synced,
                            notes: [
                                RoomScanNoteSummary(
                                    id: "note-1",
                                    text: "Note",
                                    createdAt: Date(timeIntervalSince1970: 800)
                                )
                            ]
                        )
                    ]
                )
            ],
            simulatedDelayNanoseconds: 0
        )

        let updated = try await service.updateProject(
            id: "project-1",
            name: "Updated",
            description: "After"
        )

        #expect(updated.name == "Updated")
        #expect(updated.description == "After")
        #expect(updated.roomScans.count == 1)

        let page = try await service.fetchProjects(page: 1, pageSize: 5)
        #expect(page.projects.first?.name == "Updated")
        #expect(page.projects.first?.description == "After")
    }

    @Test func deleteProjectRemovesProjectAndCascadedContentFromFeed() async throws {
        let service = MockProjectsService(
            projects: [
                ProjectSummary(
                    id: "project-1",
                    name: "Keep",
                    ownerName: "You",
                    createdAt: Date(timeIntervalSince1970: 1_900),
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    description: "",
                    sharedUserCount: 0,
                    roomScans: []
                ),
                ProjectSummary(
                    id: "project-2",
                    name: "Delete Me",
                    ownerName: "You",
                    createdAt: Date(timeIntervalSince1970: 900),
                    updatedAt: Date(timeIntervalSince1970: 1_000),
                    description: "",
                    sharedUserCount: 0,
                    roomScans: [
                        RoomScanSummary(
                            id: "scan-2",
                            name: "Kitchen",
                            createdAt: Date(timeIntervalSince1970: 900),
                            thumbnailName: "thumbnail-1",
                            syncStatus: .synced,
                            notes: [
                                RoomScanNoteSummary(
                                    id: "note-2",
                                    text: "Note",
                                    createdAt: Date(timeIntervalSince1970: 800)
                                )
                            ]
                        )
                    ]
                )
            ],
            simulatedDelayNanoseconds: 0
        )

        try await service.deleteProject(id: "project-2")

        let page = try await service.fetchProjects(page: 1, pageSize: 5)
        #expect(page.projects.map(\.id) == ["project-1"])
    }

    @Test func updateOrDeleteMissingProjectThrowsNotFound() async {
        let service = MockProjectsService(projects: [], simulatedDelayNanoseconds: 0)

        await #expect(throws: ProjectsServiceError.notFound) {
            _ = try await service.updateProject(id: "missing", name: "Name", description: "")
        }
        await #expect(throws: ProjectsServiceError.notFound) {
            try await service.deleteProject(id: "missing")
        }
    }
}
