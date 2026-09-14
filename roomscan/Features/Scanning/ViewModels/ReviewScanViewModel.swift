//
//  ReviewScanViewModel.swift
//  roomscan
//

import Combine
import Foundation

@MainActor
final class ReviewScanViewModel: ObservableObject {
    static let maxProjectPages = 100

    @Published var draft: RoomScanDraft
    @Published var scanName: String = ""
    @Published var selectedProjectID: String?
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var isLoadingProjects: Bool = false
    @Published private(set) var isSaving: Bool = false
    @Published var showCreateProjectModal: Bool = false
    @Published var showDiscardConfirmation: Bool = false
    @Published var scanNameError: String?
    @Published var projectSelectError: String?
    @Published private(set) var saveErrorMessage: String?
    @Published private(set) var savedScan: RoomScanSummary?

    private let projectsService: ProjectsService
    private let storageService: ScanStorageService
    private var previousSelectedProjectID: String?
    private var validationSequence: Int = 0
    private var cancellables = Set<AnyCancellable>()

    init(
        draft: RoomScanDraft,
        preselectedProjectID: String? = nil,
        projectsService: ProjectsService,
        storageService: ScanStorageService = LocalScanStorageService()
    ) {
        self.draft = draft
        self.projectsService = projectsService
        self.storageService = storageService
        self.selectedProjectID = preselectedProjectID ?? draft.projectID
        self.previousSelectedProjectID = self.selectedProjectID
        self.scanName = draft.name

        setupValidation()
    }

    private func setupValidation() {
        Publishers.CombineLatest($scanName, $selectedProjectID)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] name, projectID in
                guard let self = self else { return }
                self.saveErrorMessage = nil
                if projectID != nil {
                    self.projectSelectError = nil
                }
                Task {
                    await self.validateDuplicateScanName(name: name, projectID: projectID)
                }
            }
            .store(in: &cancellables)
    }

    /// Loads projects for the review picker and recovers a missing preselected project.
    ///
    /// When the selected project is absent from the paginated list, fetches it by ID and
    /// prepends it before publishing. Cancellation during recovery leaves `projects`
    /// unchanged so a partial list without the selection is never shown.
    func loadProjects() async {
        isLoadingProjects = true
        saveErrorMessage = nil
        defer {
            isLoadingProjects = false
        }
        do {
            var fetchedProjects: [ProjectSummary] = []
            var page = 1
            var hasMore = true

            while hasMore, page <= Self.maxProjectPages {
                try Task.checkCancellation()
                let result = try await projectsService.fetchProjects(page: page, pageSize: 100)
                fetchedProjects.append(contentsOf: result.projects)
                hasMore = result.hasMore
                page += 1
            }

            if hasMore {
                #if DEBUG
                print("[ReviewScanViewModel] Project pagination reached the \(Self.maxProjectPages)-page limit")
                #endif
            }

            if let selectedProjectID,
               !fetchedProjects.contains(where: { $0.id == selectedProjectID }) {
                do {
                    let project = try await projectsService.fetchProject(id: selectedProjectID)
                    fetchedProjects.insert(project, at: 0)
                } catch is CancellationError {
                    return
                } catch {
                    // Cannot keep a selection that is not in the list (the picker would
                    // still show the placeholder). Tell the user why the preselection disappeared.
                    self.selectedProjectID = nil
                    self.saveErrorMessage = String(localized: "review.error.load_projects_failed")
                }
            }

            self.projects = fetchedProjects
        } catch is CancellationError {
            return
        } catch {
            self.saveErrorMessage = String(localized: "review.error.load_projects_failed")
        }
    }

    func openCreateProjectModal() {
        previousSelectedProjectID = selectedProjectID
        showCreateProjectModal = true
    }

    func cancelCreateProjectModal() {
        selectedProjectID = previousSelectedProjectID
        if selectedProjectID == nil {
            projectSelectError = String(localized: "review.error.select_project")
        }
        showCreateProjectModal = false
    }

    func createProject(name: String) async -> Bool {
        do {
            let newProject = try await projectsService.createProject(name: name, projectDescription: "")
            await loadProjects()
            selectedProjectID = newProject.id
            previousSelectedProjectID = newProject.id
            showCreateProjectModal = false
            return true
        } catch {
            return false
        }
    }

    var isSaveEnabled: Bool {
        let trimmed = scanName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 50 else { return false }
        guard let projectID = selectedProjectID, !projectID.isEmpty else { return false }
        guard scanNameError == nil else { return false }
        return !isSaving
    }

    private func validateDuplicateScanName(name: String, projectID: String?) async {
        validationSequence += 1
        let currentSequence = validationSequence

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let projectID = projectID, !projectID.isEmpty else {
            if currentSequence == self.validationSequence {
                self.scanNameError = nil
            }
            return
        }

        do {
            let isDuplicate = try await projectsService.isScanNameDuplicate(name: trimmed, projectID: projectID)
            guard currentSequence == self.validationSequence else { return }

            if isDuplicate {
                self.scanNameError = String(localized: "review.error.duplicate_name")
            } else {
                self.scanNameError = nil
            }
        } catch {
            guard currentSequence == self.validationSequence else { return }
            self.scanNameError = nil
        }
    }

    func saveScan() async -> RoomScanSummary? {
        guard let projectID = selectedProjectID else {
            projectSelectError = String(localized: "review.error.select_project")
            return nil
        }
        let trimmedName = scanName.trimmingCharacters(in: .whitespacesAndNewlines)

        await validateDuplicateScanName(name: trimmedName, projectID: projectID)
        guard isSaveEnabled else { return nil }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        do {
            let requestChanged = draft.createScanRequestName != trimmedName
                || draft.createScanRequestProjectID != projectID
            // Bind the key to the exact request identity. A changed name or
            // project must never reuse a key persisted for another request.
            if draft.createScanIdempotencyKey == nil || requestChanged {
                draft.createScanIdempotencyKey = UUID().uuidString
                draft.createScanRequestName = trimmedName
                draft.createScanRequestProjectID = projectID
                draft.name = trimmedName
                draft.projectID = projectID
                try storageService.saveDraftManifest(draft)
            }
            let storedFiles = try storageService.persistSavedScan(draft: draft, scanID: draft.id)

            let saved = try await projectsService.saveScan(
                draft: draft,
                name: trimmedName,
                projectID: projectID,
                meshURL: storedFiles.meshURL
            )
            self.savedScan = saved
            cleanupDraftCache()
            return saved
        } catch ProjectsServiceError.duplicateScanName {
            storageService.deleteScanFiles(scanID: draft.id)
            self.scanNameError = String(localized: "review.error.duplicate_name")
            return nil
        } catch {
            // A failed upload is cleaned up by the remote service; invalidate
            // the key so a later retry creates a fresh remote scan.
            draft.createScanIdempotencyKey = nil
            draft.createScanRequestName = nil
            draft.createScanRequestProjectID = nil
            try? storageService.saveDraftManifest(draft)
            storageService.deleteScanFiles(scanID: draft.id)
            saveErrorMessage = String(localized: "review.error.save_failed")
            return nil
        }
    }

    func cleanupDraftCache() {
        storageService.clearDraftManifest()
        draft.deleteManagedFiles()
    }
}
