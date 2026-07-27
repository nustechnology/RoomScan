//
//  ReviewScanViewModelTests.swift
//  roomscanTests
//

import XCTest
@testable import roomscan

@MainActor
final class ReviewScanViewModelTests: XCTestCase {
    private var mockProjectsService: MockProjectsService!
    private var dummyDraft: RoomScanDraft!

    override func setUp() async throws {
        try await super.setUp()
        mockProjectsService = MockProjectsService(simulatedDelayNanoseconds: 0)

        let tempMesh = FileManager.default.temporaryDirectory.appendingPathComponent("test_mesh.usdz")
        let tempThumb = FileManager.default.temporaryDirectory.appendingPathComponent("test_thumb.jpg")
        try? "mesh".data(using: .utf8)?.write(to: tempMesh)
        try? "thumb".data(using: .utf8)?.write(to: tempThumb)

        dummyDraft = RoomScanDraft(
            meshFileURL: tempMesh,
            thumbnailFileURL: tempThumb,
            name: "Bedroom"
        )
    }

    override func tearDown() async throws {
        mockProjectsService = nil
        dummyDraft = nil
        try await super.tearDown()
    }

    func testLoadProjects_populatesProjectsListWithoutAutoSelecting() async {
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            projectsService: mockProjectsService
        )

        await viewModel.loadProjects()

        XCTAssertFalse(viewModel.projects.isEmpty)
        XCTAssertNil(viewModel.selectedProjectID)
    }

    func testPreselectedProjectID_honoredOnInit() async {
        let targetProjectID = "project-2"
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: targetProjectID,
            projectsService: mockProjectsService
        )

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.selectedProjectID, targetProjectID)
    }

    func testValidation_emptyName_disablesSave() async {
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            projectsService: mockProjectsService
        )
        await viewModel.loadProjects()

        viewModel.scanName = "   "

        XCTAssertFalse(viewModel.isSaveEnabled)
    }

    func testValidation_nameOver50Chars_disablesSave() async {
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            projectsService: mockProjectsService
        )
        await viewModel.loadProjects()

        viewModel.scanName = String(repeating: "A", count: 51)

        XCTAssertFalse(viewModel.isSaveEnabled)
    }

    func testValidation_duplicateScanName_showsErrorAndDisablesSave() async {
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: "project-1",
            projectsService: mockProjectsService
        )
        await viewModel.loadProjects()

        // "Living Room" already exists in project-1
        viewModel.scanName = "Living Room"

        // Wait for Combine debounce
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNotNil(viewModel.scanNameError)
        XCTAssertFalse(viewModel.isSaveEnabled)
    }

    func testCreateInlineProject_createsAndAutoSelects() async {
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            projectsService: mockProjectsService
        )
        await viewModel.loadProjects()

        let created = await viewModel.createProject(name: "Villa Renovation")

        XCTAssertTrue(created)
        XCTAssertEqual(viewModel.projects.first?.name, "Villa Renovation")
        XCTAssertEqual(viewModel.selectedProjectID, viewModel.projects.first?.id)
    }

    func testSaveScan_createsScanAndCleansCache() async {
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: "project-1",
            projectsService: mockProjectsService
        )
        await viewModel.loadProjects()
        viewModel.scanName = "Unique Guest Room"

        try? await Task.sleep(nanoseconds: 400_000_000)

        let saved = await viewModel.saveScan()

        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.name, "Unique Guest Room")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dummyDraft.meshFileURL.path))
    }

    func testSaveScan_whenPersistenceFails_exposesUserFacingError() async {
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: "project-1",
            projectsService: mockProjectsService,
            storageService: FailingScanStorageService()
        )
        await viewModel.loadProjects()
        viewModel.scanName = "Unique Office"
        try? await Task.sleep(nanoseconds: 400_000_000)

        let saved = await viewModel.saveScan()

        XCTAssertNil(saved)
        XCTAssertNotNil(viewModel.saveErrorMessage)
    }

    func testLoadProjects_whenFails_exposesErrorMessage() async {
        let failingService = FailingProjectsService()
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            projectsService: failingService
        )

        await viewModel.loadProjects()

        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertNotNil(viewModel.saveErrorMessage)
    }
}

private actor FailingProjectsService: ProjectsService {
    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage { throw ProjectsServiceError.network }
    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary] { throw ProjectsServiceError.network }
    func createProject(name: String) async throws -> ProjectSummary { throw ProjectsServiceError.network }
    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary { throw ProjectsServiceError.network }
    func deleteProject(id: String) async throws { throw ProjectsServiceError.network }
    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool { false }
    func saveScan(draft: RoomScanDraft, name: String, projectID: String) async throws -> RoomScanSummary { throw ProjectsServiceError.network }
}

private final class FailingScanStorageService: ScanStorageService, @unchecked Sendable {
    func saveDraftManifest(_ draft: RoomScanDraft) throws {}
    func loadDraftManifest() -> RoomScanDraft? { nil }
    func clearDraftManifest() {}

    func persistSavedScan(
        draft: RoomScanDraft,
        scanID: String
    ) throws -> (meshURL: URL, thumbnailURL: URL) {
        throw CocoaError(.fileWriteUnknown)
    }

    func deleteScanFiles(scanID: String) {}
}
