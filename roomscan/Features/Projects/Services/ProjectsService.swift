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
    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary
    func deleteProject(id: String) async throws
    func fetchAllProjectsSortedByUpdated() async throws -> [ProjectSummary]
    func createProject(name: String) async throws -> ProjectSummary
    func isScanNameDuplicate(name: String, projectID: String) async throws -> Bool
    func saveScan(draft: RoomScanDraft, name: String, projectID: String) async throws -> RoomScanSummary
    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary
    func deleteScan(projectID: String, scanID: String) async throws
    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary
}

enum ProjectsServiceError: Error, Equatable {
    case network
    case invalidPagination
    case notFound
    case invalidName
    case projectNotFound
    case duplicateScanName
    case invalidProjectName
    case invalidScanName
}
