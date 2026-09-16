//
//  ReviewScanViewModelTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

@MainActor
final class ReviewScanViewModelTests: XCTestCase {
    private var mockProjectsService: MockProjectsService!
    private var dummyDraft: RoomScanDraft!
    private var tempDirectoryURL: URL?

    override func setUp() async throws {
        try await super.setUp()
        mockProjectsService = MockProjectsService(simulatedDelayNanoseconds: 0)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectoryURL = tempDir

        let tempMesh = tempDir.appendingPathComponent("test_mesh.usdz")
        let tempThumb = tempDir.appendingPathComponent("test_thumb.jpg")
        try Data("mesh".utf8).write(to: tempMesh)
        try Data("thumb".utf8).write(to: tempThumb)

        dummyDraft = RoomScanDraft(
            meshFileURL: tempMesh,
            thumbnailFileURL: tempThumb,
            name: "Bedroom"
        )
    }

    override func tearDown() async throws {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: dummyDraft.meshFileURL.path))
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

    func testLoadProjects_whenCancelled_doesNotExposeErrorMessage() async {
        let cancellingService = FailingProjectsService(fetchProjectsBehavior: .cancellation)
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            projectsService: cancellingService
        )

        await viewModel.loadProjects()

        XCTAssertNil(viewModel.saveErrorMessage)
        XCTAssertFalse(viewModel.isLoadingProjects)
    }

    func testLoadProjects_stopsAtMaximumPageLimit() async {
        let paginatedService = FailingProjectsService(fetchProjectsBehavior: .alwaysHasMore)
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            projectsService: paginatedService
        )

        await viewModel.loadProjects()

        let callCount = await paginatedService.fetchProjectsCallCount()
        XCTAssertEqual(callCount, ReviewScanViewModel.maxProjectPages)
        XCTAssertNil(viewModel.saveErrorMessage)
    }

    /// Preselected project missing from the list is fetched by ID and kept selected.
    func testLoadProjects_recoversPreselectedProjectMissingFromList() async {
        let missingProject = ProjectSummary(
            id: "missing-from-list",
            name: "Recovered Project",
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: "",
            sharedUserCount: 0,
            roomScans: []
        )
        let service = SelectiveProjectsService(
            listedProjects: [],
            fetchableProjects: [missingProject]
        )
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: missingProject.id,
            projectsService: service
        )

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.selectedProjectID, missingProject.id)
        XCTAssertEqual(viewModel.projects.first?.id, missingProject.id)
        XCTAssertEqual(viewModel.projects.first?.name, "Recovered Project")
    }

    /// Stale preselection is cleared when list load and fetch-by-ID both fail to find it.
    func testLoadProjects_clearsPreselectedProjectWhenFetchAlsoFails() async {
        let service = SelectiveProjectsService(
            listedProjects: [],
            fetchableProjects: []
        )
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: "stale-project",
            projectsService: service
        )

        await viewModel.loadProjects()

        XCTAssertNil(viewModel.selectedProjectID)
        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertEqual(
            viewModel.saveErrorMessage,
            String(localized: "review.error.preselected_project_unavailable")
        )
    }

    /// Cancellation during recovery keeps the selection and leaves the already published list in place.
    func testLoadProjects_whenRecoveryCancelled_keepsSelectionAndPublishedList() async {
        let listedProject = ProjectSummary(
            id: "listed-only",
            name: "Listed Only",
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: "",
            sharedUserCount: 0,
            roomScans: []
        )
        let service = SelectiveProjectsService(
            listedProjects: [listedProject],
            fetchableProjects: [],
            fetchProjectBehavior: .cancellation
        )
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: "preselected-project",
            projectsService: service
        )

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.selectedProjectID, "preselected-project")
        XCTAssertEqual(viewModel.projects.map(\.id), [listedProject.id])
        XCTAssertNil(viewModel.saveErrorMessage)
        XCTAssertFalse(viewModel.isLoadingProjects)
    }

    /// The paginated list is visible before the missing-project recovery request finishes.
    func testLoadProjects_publishesListBeforePreselectedProjectRecovery() async {
        let listedProject = ProjectSummary(
            id: "listed-only",
            name: "Listed Only",
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: "",
            sharedUserCount: 0,
            roomScans: []
        )
        let recoveredProject = ProjectSummary(
            id: "preselected-project",
            name: "Recovered Project",
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: "",
            sharedUserCount: 0,
            roomScans: []
        )
        let service = SuspendedFetchProjectService(listedProjects: [listedProject])
        let viewModel = ReviewScanViewModel(
            draft: dummyDraft,
            preselectedProjectID: recoveredProject.id,
            projectsService: service
        )

        let loadTask = Task { await viewModel.loadProjects() }
        await service.waitUntilFetchProjectStarted()

        XCTAssertEqual(viewModel.projects.map(\.id), [listedProject.id])
        XCTAssertEqual(viewModel.selectedProjectID, recoveredProject.id)
        XCTAssertFalse(viewModel.isLoadingProjects)

        await service.resumeFetchProject(with: recoveredProject)
        await loadTask.value

        XCTAssertEqual(viewModel.projects.map(\.id), [recoveredProject.id, listedProject.id])
        XCTAssertFalse(viewModel.isLoadingProjects)
    }
}

/// Shared unused `ProjectsService` stubs for ReviewScan unit-test doubles.
private protocol ReviewScanUnusedProjectsServiceStubs: ProjectsService {}

extension ReviewScanUnusedProjectsServiceStubs {
    func createProject(name: String, projectDescription: String) async throws -> ProjectSummary {
        throw ProjectsServiceError.network
    }

    func updateProject(id: String, name: String, description: String, revision: Int) async throws -> ProjectSummary {
        throw ProjectsServiceError.network
    }

    func deleteProject(id: String) async throws {
        throw ProjectsServiceError.network
    }

    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool { false }

    func saveScan(draft: RoomScanDraft, name: String, projectID: String, meshURL: URL) async throws
        -> RoomScanSummary {
        throw ProjectsServiceError.network
    }

    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary {
        throw ProjectsServiceError.network
    }

    func deleteScan(projectID: String, scanID: String) async throws {
        throw ProjectsServiceError.network
    }

    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary {
        throw ProjectsServiceError.network
    }
}

private actor FailingProjectsService: ReviewScanUnusedProjectsServiceStubs {
    enum FetchProjectsBehavior: Sendable {
        case failure
        case cancellation
        case alwaysHasMore
    }

    private let fetchProjectsBehavior: FetchProjectsBehavior
    private var fetchCount = 0

    init(fetchProjectsBehavior: FetchProjectsBehavior = .failure) {
        self.fetchProjectsBehavior = fetchProjectsBehavior
    }

    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        fetchCount += 1

        switch fetchProjectsBehavior {
        case .failure:
            throw ProjectsServiceError.network
        case .cancellation:
            throw CancellationError()
        case .alwaysHasMore:
            return ProjectPage(projects: [], hasMore: true)
        }
    }

    func fetchProjectsCallCount() -> Int { fetchCount }

    func fetchProject(id: String) async throws -> ProjectSummary { throw ProjectsServiceError.network }

    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary] {
        throw ProjectsServiceError.network
    }
}

/// Test double that can return a different set for list vs fetch-by-ID, including cancellation.
private actor SelectiveProjectsService: ReviewScanUnusedProjectsServiceStubs {
    enum FetchProjectBehavior: Sendable {
        case useFetchableProjects
        case cancellation
    }

    private let listedProjects: [ProjectSummary]
    private let fetchableProjects: [ProjectSummary]
    private let fetchProjectBehavior: FetchProjectBehavior

    /// Creates a selective stub for list vs single-project recovery tests.
    /// - Parameters:
    ///   - listedProjects: Projects returned by paginated `fetchProjects`.
    ///   - fetchableProjects: Projects returned by `fetchProject(id:)` when not cancelling.
    ///   - fetchProjectBehavior: Controls whether `fetchProject` succeeds or cancels.
    init(
        listedProjects: [ProjectSummary],
        fetchableProjects: [ProjectSummary],
        fetchProjectBehavior: FetchProjectBehavior = .useFetchableProjects
    ) {
        self.listedProjects = listedProjects
        self.fetchableProjects = fetchableProjects
        self.fetchProjectBehavior = fetchProjectBehavior
    }

    /// Returns the configured listed page for page 1, otherwise an empty page.
    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        guard page == 1 else {
            return ProjectPage(projects: [], hasMore: false)
        }
        return ProjectPage(projects: listedProjects, hasMore: false)
    }

    /// Returns a configured project, or throws cancellation / not-found.
    func fetchProject(id: String) async throws -> ProjectSummary {
        if case .cancellation = fetchProjectBehavior {
            throw CancellationError()
        }
        guard let project = fetchableProjects.first(where: { $0.id == id }) else {
            throw ProjectsServiceError.projectNotFound
        }
        return project
    }

    /// Returns the listed projects sorted by the stub's fixed order.
    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary] { listedProjects }
}

/// Holds `fetchProject` until the test resumes it, so list publication can be observed first.
private actor SuspendedFetchProjectService: ReviewScanUnusedProjectsServiceStubs {
    private let listedProjects: [ProjectSummary]
    private var didStartFetch = false
    private var fetchStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseFetch: CheckedContinuation<ProjectSummary, Error>?

    /// Creates a stub whose list returns immediately and whose single-project fetch waits.
    init(listedProjects: [ProjectSummary]) {
        self.listedProjects = listedProjects
    }

    /// Returns the configured listed page for page 1, otherwise an empty page.
    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        guard page == 1 else {
            return ProjectPage(projects: [], hasMore: false)
        }
        return ProjectPage(projects: listedProjects, hasMore: false)
    }

    /// Suspends until `resumeFetchProject(with:)` supplies the recovered project.
    func fetchProject(id: String) async throws -> ProjectSummary {
        didStartFetch = true
        let waiters = fetchStartedWaiters
        fetchStartedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            releaseFetch = continuation
        }
    }

    /// Returns the listed projects in the stub's fixed order.
    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary] { listedProjects }

    /// Waits until `fetchProject` has started, which is after the list has been published.
    func waitUntilFetchProjectStarted() async {
        if didStartFetch { return }
        await withCheckedContinuation { continuation in
            fetchStartedWaiters.append(continuation)
        }
    }

    /// Completes the suspended `fetchProject` call.
    func resumeFetchProject(with project: ProjectSummary) {
        releaseFetch?.resume(returning: project)
        releaseFetch = nil
    }
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
