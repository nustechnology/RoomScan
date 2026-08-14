//
//  ModelLoadingServiceTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct ModelLoadingServiceTests {
    @Test func explicitSampleURLResolvesToSampleRoom() async throws {
        let service = DefaultModelLoadingService()

        let source = try await service.resolveSource(modelURL: DefaultModelLoadingService.mockSampleURL)

        #expect(source == .sampleRoom)
    }

    @Test func nilURLThrows() async {
        let service = DefaultModelLoadingService()

        do {
            _ = try await service.resolveSource(modelURL: nil)
            Issue.record("Expected fileNotFound")
        } catch let error as ModelLoadingError {
            #expect(error == .fileNotFound)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func missingFileThrows() async {
        let service = DefaultModelLoadingService()
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).usdz")

        do {
            _ = try await service.resolveSource(modelURL: missing)
            Issue.record("Expected fileNotFound")
        } catch let error as ModelLoadingError {
            #expect(error == .fileNotFound)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}
