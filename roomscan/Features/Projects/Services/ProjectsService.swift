//
//  ProjectsService.swift
//  roomscan
//

import Foundation

protocol ProjectsService: Sendable {
    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage
    func updateProject(id: String, name: String, description: String) async throws -> ProjectSummary
    func deleteProject(id: String) async throws
}

enum ProjectsServiceError: Error, Equatable {
    case network
    case invalidPagination
    case notFound
}
