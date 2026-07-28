//
//  ProjectsService.swift
//  roomscan
//

import Foundation

protocol ProjectsService: Sendable {
    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage
    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary
    func deleteProject(id: String) async throws
    func renameScan(projectID: String, scanID: String, name: String) async throws -> RoomScanSummary
    func deleteScan(projectID: String, scanID: String) async throws
    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary
}

enum ProjectsServiceError: Error, Equatable {
    case network
    case invalidPagination
    case notFound
    case invalidName
}
