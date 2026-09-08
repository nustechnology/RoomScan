//
//  LocalScanStorageServiceTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class LocalScanStorageServiceTests: XCTestCase {
    private var service: LocalScanStorageService!
    private var tempDirectoryURL: URL?
    private var tempMeshURL: URL!
    private var tempThumbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = LocalScanStorageService()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectoryURL = tempDir

        tempMeshURL = tempDir.appendingPathComponent("temp_mesh.usdz")
        tempThumbURL = tempDir.appendingPathComponent("temp_thumb.jpg")

        try Data("mesh data".utf8).write(to: tempMeshURL)
        try Data("thumb data".utf8).write(to: tempThumbURL)
    }

    override func tearDownWithError() throws {
        service?.clearDraftManifest()
        if let tempDirectoryURL {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        service = nil
        try super.tearDownWithError()
    }

    func testDraftManifest_saveAndLoad_returnsSavedDraft() throws {
        let draft = RoomScanDraft(
            id: "draft-123",
            meshFileURL: tempMeshURL,
            thumbnailFileURL: tempThumbURL,
            name: "Master Suite",
            projectID: "project-1"
        )

        try service.saveDraftManifest(draft)

        let loaded = service.loadDraftManifest()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "draft-123")
        XCTAssertEqual(loaded?.name, "Master Suite")
        XCTAssertEqual(loaded?.projectID, "project-1")
    }

    func testClearDraftManifest_removesManifestFile() throws {
        let draft = RoomScanDraft(
            id: "draft-456",
            meshFileURL: tempMeshURL,
            thumbnailFileURL: tempThumbURL
        )

        try service.saveDraftManifest(draft)
        service.clearDraftManifest()

        let loaded = service.loadDraftManifest()
        XCTAssertNil(loaded)
    }

    func testPersistSavedScan_copiesFilesAndKeepsManifestUntilTransactionCompletes() throws {
        let draft = RoomScanDraft(
            id: "draft-789",
            meshFileURL: tempMeshURL,
            thumbnailFileURL: tempThumbURL
        )
        try service.saveDraftManifest(draft)
        defer {
            service.deleteScanFiles(scanID: "scan-789")
        }

        let result = try service.persistSavedScan(draft: draft, scanID: "scan-789")

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.meshURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.thumbnailURL.path))
        XCTAssertNotNil(service.loadDraftManifest())
        XCTAssertTrue(service.meshExists(scanID: "scan-789"))
    }

    func testMeshExists_isFalseWhenScanWasNeverPersisted() {
        XCTAssertFalse(service.meshExists(scanID: "missing-scan"))
    }

    func testMeshExists_isFalseForUnsafeScanIDs() {
        XCTAssertFalse(service.meshExists(scanID: ""))
        XCTAssertFalse(service.meshExists(scanID: ".."))
        XCTAssertFalse(service.meshExists(scanID: "foo/bar"))
    }

    func testExistingMeshScanIDs_returnsOnlyCandidatesWithLocalMesh() async throws {
        let draft = RoomScanDraft(
            id: "draft-batch",
            meshFileURL: tempMeshURL,
            thumbnailFileURL: tempThumbURL
        )
        try service.saveDraftManifest(draft)
        defer {
            service.deleteScanFiles(scanID: "scan-present")
            service.clearDraftManifest()
        }

        _ = try service.persistSavedScan(draft: draft, scanID: "scan-present")

        let result = await service.existingMeshScanIDs(
            in: ["scan-present", "scan-missing", "..", "foo/bar", ""]
        )

        XCTAssertEqual(result, ["scan-present"])
    }

    func testExistingMeshScanIDs_ignoresScanDirectoryWithoutMeshFile() async throws {
        let scansRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scans", isDirectory: true)
        let emptyScanDir = scansRoot.appendingPathComponent("scan-empty-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyScanDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: emptyScanDir)
        }

        let result = await service.existingMeshScanIDs(in: ["scan-empty-dir"])

        XCTAssertTrue(result.isEmpty)
    }
}
