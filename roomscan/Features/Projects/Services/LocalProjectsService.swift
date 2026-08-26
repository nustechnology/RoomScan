//
//  LocalProjectsService.swift
//  roomscan
//

import Foundation

@MainActor
final class LocalProjectsService: ProjectsLocalCache, @unchecked Sendable {
    private var projects: [ProjectSummary]
    private let storeURL: URL
    private let scanStorageService: ScanStorageService

    enum LoadResult {
        case fileNotFound
        case success([ProjectSummary])
        case decodeFailed(Error)
    }

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        scanStorageService: ScanStorageService = LocalScanStorageService(),
        seedIfEmpty: Bool = true
    ) {
        self.scanStorageService = scanStorageService
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseDirectory = directory
            ?? supportDirectory.appendingPathComponent("RoomScan", isDirectory: true)

        try? fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        let url = baseDirectory.appendingPathComponent("projects.json")
        storeURL = url

        switch Self.loadProjects(from: url, fileManager: fileManager) {
        case .fileNotFound:
            let seeds = seedIfEmpty ? Self.initialProjects() : []
            self.projects = seeds
            try? Self.persist(projects: seeds, to: url)

        case .success(let loadedProjects):
            self.projects = loadedProjects

        case .decodeFailed(let error):
            print("[LocalProjectsService ERROR] Corrupted or unreadable projects store at \(url.path): \(error)")
            Self.backupCorruptedFile(at: url, fileManager: fileManager)
            self.projects = seedIfEmpty ? Self.initialProjects() : []
        }
    }

    private static func initialProjects() -> [ProjectSummary] {
        #if DEBUG
        return MockProjectsService.makeSeedProjects()
        #else
        return []
        #endif
    }

    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage {
        guard page >= 1, pageSize > 0 else {
            throw ProjectsServiceError.invalidPagination
        }

        let sortedProjects = projects.sorted { $0.updatedAt > $1.updatedAt }
        let startIndex = (page - 1) * pageSize
        guard startIndex < sortedProjects.count else {
            return ProjectPage(projects: [], hasMore: false)
        }

        let endIndex = min(startIndex + pageSize, sortedProjects.count)
        return ProjectPage(
            projects: Array(sortedProjects[startIndex..<endIndex]),
            hasMore: endIndex < sortedProjects.count
        )
    }

    func fetchProject(id: String) async throws -> ProjectSummary {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw ProjectsServiceError.projectNotFound
        }
        return project
    }

    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary] {
        projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    func updateProject(id: String, name: String, description: String, revision: Int = 1) async throws -> ProjectSummary {
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectsServiceError.projectNotFound
        }
        let existing = projects[index]
        let updated = ProjectSummary(
            id: existing.id,
            name: name,
            ownerName: existing.ownerName,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            description: description,
            sharedUserCount: existing.sharedUserCount,
            roomScans: existing.roomScans,
            scanCount: existing.scanCount
        )
        projects[index] = updated
        projects.sort { $0.updatedAt > $1.updatedAt }
        try persist()
        return updated
    }

    func deleteProject(id: String) async throws {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw ProjectsServiceError.projectNotFound
        }
        projects.removeAll { $0.id == id }
        try persist()
        for scan in project.roomScans {
            scanStorageService.deleteScanFiles(scanID: localStorageID(for: scan))
        }
    }

    func createProject(name: String, projectDescription: String) async throws -> ProjectSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 50 else {
            throw ProjectsServiceError.invalidProjectName
        }
        guard trimmedDescription.count <= 500 else {
            throw ProjectsServiceError.invalidProjectName
        }

        let project = ProjectSummary(
            id: UUID().uuidString,
            name: trimmedName,
            ownerName: "You",
            createdAt: Date(),
            updatedAt: Date(),
            description: trimmedDescription,
            sharedUserCount: 0,
            roomScans: []
        )
        projects.insert(project, at: 0)
        try persist()
        return project
    }

    func writeCachedProject(_ project: ProjectSummary, mergingLocalScans: Bool) throws {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = mergingLocalScans
                ? ProjectSummary.mergingRemoteCache(project, over: projects[index])
                : project
        } else {
            projects.insert(project, at: 0)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
        try persist()
    }

    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return false
        }
        return project.roomScans.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    func saveScan(
        draft: RoomScanDraft,
        name: String,
        projectID: String,
        meshURL: URL
    ) async throws -> RoomScanSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 50 else {
            throw ProjectsServiceError.invalidScanName
        }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectsServiceError.projectNotFound
        }
        guard !projects[projectIndex].roomScans.contains(where: {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) else {
            throw ProjectsServiceError.duplicateScanName
        }

        let scan = RoomScanSummary(
            id: draft.id,
            name: trimmedName,
            createdAt: draft.createdAt,
            localModelURL: meshURL,
            thumbnailName: "thumbnail.jpg",
            syncStatus: .pending,
            notes: []
        )
        var scans = projects[projectIndex].roomScans
        scans.insert(scan, at: 0)
        projects[projectIndex] = projects[projectIndex].withRoomScans(scans, scanCountDelta: 1)
        projects.sort { $0.updatedAt > $1.updatedAt }
        try persist()
        return scan
    }

    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectsServiceError.invalidScanName
        }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectsServiceError.projectNotFound
        }
        let project = projects[projectIndex]
        guard let existing = project.roomScans.first(where: { $0.id == scanID }) else {
            throw ProjectsServiceError.notFound
        }

        let updated = RoomScanSummary(
            id: existing.id,
            name: trimmedName,
            createdAt: existing.createdAt,
            localModelURL: existing.localModelURL,
            thumbnailName: existing.thumbnailName,
            syncStatus: existing.syncStatus,
            creatorUserID: existing.creatorUserID,
            creatorDisplayName: existing.creatorDisplayName,
            notes: existing.notes,
            meshPath: existing.meshPath,
            thumbnailPath: existing.thumbnailPath,
            noteCount: existing.noteCount
        )
        guard let updatedProject = project.replacingScan(updated) else {
            throw ProjectsServiceError.notFound
        }
        projects[projectIndex] = updatedProject
        projects.sort { $0.updatedAt > $1.updatedAt }
        try persist()
        return updated
    }

    func deleteScan(projectID: String, scanID: String) async throws {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectsServiceError.projectNotFound
        }
        let project = projects[projectIndex]
        guard let scan = project.roomScans.first(where: { $0.id == scanID }) else {
            throw ProjectsServiceError.notFound
        }

        projects[projectIndex] = project.removingScan(id: scanID)
        projects.sort { $0.updatedAt > $1.updatedAt }
        try persist()
        scanStorageService.deleteScanFiles(scanID: localStorageID(for: scan))
    }

    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectsServiceError.projectNotFound
        }
        let project = projects[projectIndex]
        guard let existing = project.roomScans.first(where: { $0.id == scanID }) else {
            throw ProjectsServiceError.notFound
        }

        let updated = RoomScanSummary(
            id: existing.id,
            name: existing.name,
            createdAt: existing.createdAt,
            localModelURL: existing.localModelURL,
            thumbnailName: existing.thumbnailName,
            syncStatus: .pending,
            creatorUserID: existing.creatorUserID,
            creatorDisplayName: existing.creatorDisplayName,
            notes: existing.notes,
            meshPath: existing.meshPath,
            thumbnailPath: existing.thumbnailPath,
            noteCount: existing.noteCount
        )
        guard let updatedProject = project.replacingScan(updated) else {
            throw ProjectsServiceError.notFound
        }
        projects[projectIndex] = updatedProject
        projects.sort { $0.updatedAt > $1.updatedAt }
        try persist()
        return updated
    }

    private func persist() throws {
        try Self.persist(projects: projects, to: storeURL)
    }

    private func localStorageID(for scan: RoomScanSummary) -> String {
        guard let modelURL = scan.localModelURL,
              modelURL.lastPathComponent == "mesh.usdz",
              modelURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Scans" else {
            return scan.id
        }
        return modelURL.deletingLastPathComponent().lastPathComponent
    }

    private static func persist(projects: [ProjectSummary], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(projects)
        try data.write(to: url, options: .atomic)
    }

    private static func loadProjects(from url: URL, fileManager: FileManager) -> LoadResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .fileNotFound
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let projects = try decoder.decode([ProjectSummary].self, from: data)
            return .success(projects)
        } catch {
            return .decodeFailed(error)
        }
    }

    private static func backupCorruptedFile(at url: URL, fileManager: FileManager) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("corrupted.\(timestamp).json")
        do {
            try fileManager.copyItem(at: url, to: backupURL)
            print("[LocalProjectsService] Backed up corrupted store to \(backupURL.path)")
        } catch {
            print("[LocalProjectsService ERROR] Failed to backup corrupted store: \(error)")
        }
    }
}
