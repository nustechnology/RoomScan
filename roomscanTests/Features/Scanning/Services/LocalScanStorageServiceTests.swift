//
//  LocalScanStorageServiceTests.swift
//  roomscanTests
//

import XCTest
@testable import roomscan

final class LocalScanStorageServiceTests: XCTestCase {
    private var service: LocalScanStorageService!
    private var tempMeshURL: URL!
    private var tempThumbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = LocalScanStorageService()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        tempMeshURL = tempDir.appendingPathComponent("temp_mesh.usdz")
        tempThumbURL = tempDir.appendingPathComponent("temp_thumb.jpg")

        try "mesh data".data(using: .utf8)?.write(to: tempMeshURL)
        try "thumb data".data(using: .utf8)?.write(to: tempThumbURL)
    }

    override func tearDown() {
        service = nil
        super.tearDown()
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

        let result = try service.persistSavedScan(draft: draft, scanID: "scan-789")

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.meshURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.thumbnailURL.path))
        XCTAssertNotNil(service.loadDraftManifest())

        // Cleanup
        service.clearDraftManifest()
        service.deleteScanFiles(scanID: "scan-789")
    }
}
