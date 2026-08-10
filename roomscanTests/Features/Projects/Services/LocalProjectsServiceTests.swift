//
//  LocalProjectsServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct LocalProjectsServiceTests {
    @Test func init_whenStoreDoesNotExist_seedsInitialProjects() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let service = LocalProjectsService(directory: tempDir)
        let page = try await service.fetchProjects(page: 1, pageSize: 10)
        #expect(!page.projects.isEmpty)
    }

    @Test func fetchAllProjects_returnsSortedProjects() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let service = LocalProjectsService(directory: tempDir)
        let projects = try await service.fetchAllProjectsSortedByUpdated()
        #expect(!projects.isEmpty)
        guard projects.count > 1 else { return }
        for index in 0..<(projects.count - 1) {
            #expect(projects[index].updatedAt >= projects[index + 1].updatedAt)
        }
    }

    @Test func saveScan_preservesProjectDescription() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let service = LocalProjectsService(directory: tempDir)
        let project = try await service.createProject(name: "Test Project With Description", projectDescription: "")
        _ = try await service.updateProject(id: project.id, name: "Test Project With Description", description: "Custom Description")

        let tempMesh = tempDir.appendingPathComponent("test_mesh_\(UUID().uuidString).usdz")
        let tempThumb = tempDir.appendingPathComponent("test_thumb_\(UUID().uuidString).jpg")
        try Data("mesh".utf8).write(to: tempMesh)
        try Data("thumb".utf8).write(to: tempThumb)

        let draft = RoomScanDraft(id: UUID().uuidString, meshFileURL: tempMesh, thumbnailFileURL: tempThumb)
        _ = try await service.saveScan(draft: draft, name: "New Scan", projectID: project.id, meshURL: tempMesh)

        let projects = try await service.fetchAllProjectsSortedByUpdated()
        let updatedProject = projects.first(where: { $0.id == project.id })
        #expect(updatedProject?.description == "Custom Description")
    }

    @Test func saveScan_setsLocalModelURL_andPersistsAcrossReload() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let service = LocalProjectsService(directory: tempDir)
        let project = try await service.createProject(name: "Test Project", projectDescription: "")

        let tempMesh = tempDir.appendingPathComponent("test_mesh_\(UUID().uuidString).usdz")
        try Data("mesh".utf8).write(to: tempMesh)

        let draft = RoomScanDraft(id: UUID().uuidString, meshFileURL: tempMesh, thumbnailFileURL: tempMesh)
        let saved = try await service.saveScan(draft: draft, name: "New Scan", projectID: project.id, meshURL: tempMesh)

        #expect(saved.localModelURL == tempMesh)

        let reloadedService = LocalProjectsService(directory: tempDir)
        let projects = try await reloadedService.fetchAllProjectsSortedByUpdated()
        let scan = projects.first(where: { $0.id == project.id })?.roomScans.first
        #expect(scan?.localModelURL == tempMesh)
    }

    @Test func deleteScan_removesScanFiles() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storage = RecordingScanStorageService()
        let service = LocalProjectsService(directory: tempDir, scanStorageService: storage)
        let project = try await service.createProject(name: "Test Project", projectDescription: "")
        let mesh = tempDir.appendingPathComponent("mesh.usdz")
        try Data("mesh".utf8).write(to: mesh)
        let draft = RoomScanDraft(id: "scan-1", meshFileURL: mesh, thumbnailFileURL: mesh)
        _ = try await service.saveScan(draft: draft, name: "Scan One", projectID: project.id, meshURL: mesh)

        try await service.deleteScan(projectID: project.id, scanID: "scan-1")

        #expect(storage.deletedScanIDs == ["scan-1"])
    }

    @Test func deleteProject_removesChildScanFiles() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storage = RecordingScanStorageService()
        let service = LocalProjectsService(directory: tempDir, scanStorageService: storage)
        let project = try await service.createProject(name: "Test Project", projectDescription: "")
        for scanID in ["scan-1", "scan-2"] {
            let mesh = tempDir.appendingPathComponent("\(scanID).usdz")
            try Data("mesh".utf8).write(to: mesh)
            let draft = RoomScanDraft(id: scanID, meshFileURL: mesh, thumbnailFileURL: mesh)
            _ = try await service.saveScan(draft: draft, name: "Scan \(scanID)", projectID: project.id, meshURL: mesh)
        }

        try await service.deleteProject(id: project.id)

        #expect(Set(storage.deletedScanIDs) == Set(["scan-1", "scan-2"]))
    }

    @Test func deleteScan_whenNotFound_doesNotRemoveFiles() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storage = RecordingScanStorageService()
        let service = LocalProjectsService(directory: tempDir, scanStorageService: storage)
        let project = try await service.createProject(name: "Test Project", projectDescription: "")

        do {
            try await service.deleteScan(projectID: project.id, scanID: "missing")
            Issue.record("Expected deleteScan to throw notFound")
        } catch ProjectsServiceError.notFound {
            // expected
        }

        #expect(storage.deletedScanIDs.isEmpty)
    }

    @Test func init_whenSeedIfEmptyFalse_startsEmpty() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let service = LocalProjectsService(directory: tempDir, seedIfEmpty: false)
        let page = try await service.fetchProjects(page: 1, pageSize: 10)
        #expect(page.projects.isEmpty)
    }

    @Test func cacheProject_persistsAcrossReloadAndPreservesLocalScans() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingScan = RoomScanSummary(
            id: "scan-1",
            name: "Living Room",
            createdAt: Date(timeIntervalSince1970: 1_000),
            thumbnailName: "thumbnail-0",
            syncStatus: .synced,
            notes: []
        )
        let service = LocalProjectsService(directory: tempDir, seedIfEmpty: false)
        await service.cacheProject(
            ProjectSummary(
                id: "project-1",
                name: "Cached",
                roomScans: [existingScan],
                scanCount: 1
            )
        )

        await service.cacheProject(
            ProjectSummary(
                id: "project-1",
                name: "Updated From Remote",
                description: "Remote description",
                roomScans: [],
                scanCount: 0
            )
        )

        let reloaded = LocalProjectsService(directory: tempDir, seedIfEmpty: false)
        let project = try await reloaded.fetchProject(id: "project-1")
        #expect(project.name == "Updated From Remote")
        #expect(project.description == "Remote description")
        #expect(project.roomScans.count == 1)
        #expect(project.roomScans.first?.id == "scan-1")
        #expect(project.scanCount == 1)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalProjectsServiceTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private final class RecordingScanStorageService: ScanStorageService, @unchecked Sendable {
    private(set) var deletedScanIDs: [String] = []

    func saveDraftManifest(_ draft: RoomScanDraft) throws {}
    func loadDraftManifest() -> RoomScanDraft? { nil }
    func clearDraftManifest() {}
    func persistSavedScan(draft: RoomScanDraft, scanID: String) throws -> (meshURL: URL, thumbnailURL: URL) {
        (URL(fileURLWithPath: "/tmp/mesh.usdz"), URL(fileURLWithPath: "/tmp/thumb.jpg"))
    }
    func deleteScanFiles(scanID: String) {
        deletedScanIDs.append(scanID)
    }
}
