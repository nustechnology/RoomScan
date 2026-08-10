//
//  ProjectsService.swift
//  roomscan
//

import Foundation

@MainActor
enum ProjectsServiceFactory {
    static let shared: any ProjectsService = {
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            return MockProjectsService.makeForCurrentProcess()
        }
        return LocalProjectsService()
    }()
}

protocol ProjectsService: Sendable {
    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage
    func fetchProject(id: String) async throws -> ProjectSummary
    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary
    func deleteProject(id: String) async throws
    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary]
    func createProject(name: String, projectDescription: String) async throws -> ProjectSummary
    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool
    func saveScan(draft: RoomScanDraft, name: String, projectID: String, meshURL: URL) async throws -> RoomScanSummary
    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary
    func deleteScan(projectID: String, scanID: String) async throws
    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary
}

/// Local cache used by `RemoteProjectsService` for project metadata and scans.
protocol ProjectsLocalCache: ProjectsService {
    func cacheProject(_ project: ProjectSummary) async
}

/// Failures thrown by `ProjectsService` implementations.
///
/// Mapping (all implementations must agree):
/// - `network`: transient or simulated network failure
/// - `invalidPagination`: `page < 1` or `pageSize <= 0`
/// - `projectNotFound`: the project id does not exist
/// - `notFound`: the scan (or other nested resource) id does not exist within a known project
/// - `invalidProjectName`: project name empty or longer than 50 characters after trimming
/// - `invalidScanName`: scan name empty or over the allowed length after trimming
/// - `duplicateScanName`: a scan with the same name already exists in the project
enum ProjectsServiceError: Error, Equatable {
    case network
    case invalidPagination
    case projectNotFound
    case notFound
    case invalidProjectName
    case invalidScanName
    case duplicateScanName
}
