//
//  RealAccountStorageMeasuringTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct RealAccountStorageMeasuringTests {
    @Test func usedBytesSumsAllocatedFilesAcrossDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second/nested")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: first.appendingPathComponent("mesh.usdz"))
        try Data(repeating: 0, count: 50).write(to: second.appendingPathComponent("thumb.png"))

        let measuring = RealAccountStorageMeasuring(directories: [first, second])
        let bytes = await measuring.usedBytes()

        #expect(bytes >= 150)
    }

    @Test func usedBytesIsZeroWhenDirectoryDoesNotExist() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let measuring = RealAccountStorageMeasuring(directories: [missing])
        let bytes = await measuring.usedBytes()

        #expect(bytes == 0)
    }
}
