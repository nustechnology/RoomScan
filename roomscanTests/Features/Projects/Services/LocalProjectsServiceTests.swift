//
//  LocalProjectsServiceTests.swift
//  roomscanTests
//

import Testing
import Foundation
@testable import roomscan

@MainActor
struct LocalProjectsServiceTests {
    @Test func init_whenStoreDoesNotExist_seedsInitialProjects() async throws {
        let tempDir = makeTempDir()
        let service = LocalProjectsService(directory: tempDir)
        let page = try await service.fetchProjects(page: 1, pageSize: 10)
        #expect(!page.projects.isEmpty)
    }

    @Test func fetchAllProjects_returnsSortedProjects() async throws {
        let tempDir = makeTempDir()
        let service = LocalProjectsService(directory: tempDir)
        let projects = try await service.fetchAllProjectsSortedByUpdated()
        #expect(!projects.isEmpty)
        guard projects.count > 1 else { return }
        for index in 0..<(projects.count - 1) {
            #expect(projects[index].updatedAt >= projects[index + 1].updatedAt)
        }
    }

    @Test func saveScan_preservesProjectDescription() async throws {
        let tempDir = makeTempDir()
        let service = LocalProjectsService(directory: tempDir)
        let project = try await service.createProject(name: "Test Project With Description")
        _ = try await service.updateProject(id: project.id, name: "Test Project With Description", description: "Custom Description")

        let tempMesh = tempDir.appendingPathComponent("test_mesh_\(UUID().uuidString).usdz")
        let tempThumb = tempDir.appendingPathComponent("test_thumb_\(UUID().uuidString).jpg")
        try? "mesh".data(using: .utf8)?.write(to: tempMesh)
        try? "thumb".data(using: .utf8)?.write(to: tempThumb)

        let draft = RoomScanDraft(id: UUID().uuidString, meshFileURL: tempMesh, thumbnailFileURL: tempThumb)
        _ = try await service.saveScan(draft: draft, name: "New Scan", projectID: project.id)

        let projects = try await service.fetchAllProjectsSortedByUpdated()
        let updatedProject = projects.first(where: { $0.id == project.id })
        #expect(updatedProject?.description == "Custom Description")
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalProjectsServiceTest_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
