//
//  ReviewScanViewModel.swift
//  roomscan
//

import Combine
import Foundation

@MainActor
final class ReviewScanViewModel: ObservableObject {
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
        print("[RoomScan STEP 9.1] ReviewScanViewModel.init() started...")
        self.draft = draft
        self.projectsService = projectsService
        self.storageService = storageService
        self.selectedProjectID = preselectedProjectID ?? draft.projectID
        self.previousSelectedProjectID = self.selectedProjectID
        self.scanName = draft.name.isEmpty ? "New Room Scan" : draft.name

        print("[RoomScan STEP 9.2] ReviewScanViewModel initialized. Draft ID: \(draft.id), Mesh URL: \(draft.meshFileURL.path)")
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

    func loadProjects() async {
        print("[RoomScan STEP 11.1] ReviewScanViewModel.loadProjects() started...")
        isLoadingProjects = true
        saveErrorMessage = nil
        defer {
            isLoadingProjects = false
            print("[RoomScan STEP 11.2] ReviewScanViewModel.loadProjects() completed. Count: \(self.projects.count)")
        }
        do {
            let fetchedProjects = try await projectsService.fetchAllProjectsSortedByUpdated()
            self.projects = fetchedProjects
        } catch {
            print("[RoomScan STEP 11-ERROR] loadProjects failed: \(error.localizedDescription)")
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
            let newProject = try await projectsService.createProject(name: name)
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
            storageService.deleteScanFiles(scanID: draft.id)
            saveErrorMessage = String(localized: "review.error.save_failed")
            return nil
        }
    }

    func cleanupDraftCache() {
        storageService.clearDraftManifest()
        try? FileManager.default.removeItem(at: draft.meshFileURL)
        try? FileManager.default.removeItem(at: draft.thumbnailFileURL)
    }
}
