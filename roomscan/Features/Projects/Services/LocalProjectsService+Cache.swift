//
//  LocalProjectsService+Cache.swift
//  roomscan
//

import Foundation

extension LocalProjectsService {
    func cacheProject(_ project: ProjectSummary) async throws {
        try writeCachedProject(project, mergingLocalScans: true)
    }

    func replaceCachedProject(_ project: ProjectSummary) async throws {
        try writeCachedProject(project, mergingLocalScans: false)
    }
}
