//
//  ProjectsService.swift
//  roomscan
//

import Foundation

protocol ProjectsService: Sendable {
    func fetchProjects(page: Int, pageSize: Int) async throws -> ProjectPage
}

enum ProjectsServiceError: Error, Equatable {
    case network
    case invalidPagination
}
