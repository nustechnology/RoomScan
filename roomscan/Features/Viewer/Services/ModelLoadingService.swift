//
//  ModelLoadingService.swift
//  roomscan
//

import Foundation

protocol ModelLoadingService: AnyObject {
    func resolveSource(modelURL: URL?) async throws -> ModelSource
}

/// Resolves a local model file URL. Missing URLs surface as a load failure.
final class DefaultModelLoadingService: ModelLoadingService {
    static let mockSampleURL = URL(string: "roomscan-sample://viewer/sample-room")!

    func resolveSource(modelURL: URL?) async throws -> ModelSource {
        guard let modelURL else {
            throw ModelLoadingError.fileNotFound
        }

        if modelURL == Self.mockSampleURL {
            return .sampleRoom
        }

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw ModelLoadingError.fileNotFound
        }

        return .file(modelURL)
    }
}
