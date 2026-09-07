//
//  RealAccountStorageMeasuringTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

@MainActor
struct RealAccountStorageMeasuringTests {
    @Test func usedBytesSumsSelectedScanFoldersAndSharedDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let scansRoot = root.appendingPathComponent("Scans")
        let currentUserScan = scansRoot.appendingPathComponent("user-b-scan")
        let otherUserScan = scansRoot.appendingPathComponent("user-a-scan")
        let caches = root.appendingPathComponent("Caches")
        let drafts = root.appendingPathComponent("Drafts")
        let ignoredSupport = root.appendingPathComponent("Application Support")

        for directory in [currentUserScan, otherUserScan, caches, drafts, ignoredSupport] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try Data(repeating: 0, count: 100).write(to: currentUserScan.appendingPathComponent("mesh.usdz"))
        try Data(repeating: 0, count: 50).write(to: otherUserScan.appendingPathComponent("mesh.usdz"))
        try Data(repeating: 0, count: 20).write(to: caches.appendingPathComponent("cache.dat"))
        try Data(repeating: 0, count: 10).write(to: drafts.appendingPathComponent("draft.usdz"))
        try Data(repeating: 0, count: 500).write(to: ignoredSupport.appendingPathComponent("projects.json"))

        let measuring = RealAccountStorageMeasuring(
            scansRoot: scansRoot,
            sharedDirectories: [caches, drafts]
        )
        let sharedOnlyBytes = await measuring.usedBytes(forScanIDs: [])
        let currentUserBytes = await measuring.usedBytes(forScanIDs: ["user-b-scan"])
        let bothUsersBytes = await measuring.usedBytes(forScanIDs: ["user-b-scan", "user-a-scan"])

        #expect(currentUserBytes > sharedOnlyBytes)
        #expect(bothUsersBytes > currentUserBytes)
    }

    @Test func usedBytesIgnoresScanFoldersNotInTheRequestedIDs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let scansRoot = root.appendingPathComponent("Scans")
        let included = scansRoot.appendingPathComponent("included")
        let excluded = scansRoot.appendingPathComponent("excluded")
        try FileManager.default.createDirectory(at: included, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 40).write(to: included.appendingPathComponent("mesh.usdz"))
        try Data(repeating: 0, count: 400).write(to: excluded.appendingPathComponent("mesh.usdz"))

        let measuring = RealAccountStorageMeasuring(
            scansRoot: scansRoot,
            sharedDirectories: []
        )
        let includedOnly = await measuring.usedBytes(forScanIDs: ["included"])
        let both = await measuring.usedBytes(forScanIDs: ["included", "excluded"])

        #expect(includedOnly >= 40)
        #expect(both > includedOnly)
    }

    @Test func usedBytesIsZeroWhenDirectoryDoesNotExist() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let measuring = RealAccountStorageMeasuring(
            scansRoot: missing.appendingPathComponent("Scans"),
            sharedDirectories: [missing]
        )
        let bytes = await measuring.usedBytes(forScanIDs: ["scan-1"])

        #expect(bytes == 0)
    }

    @Test func usedBytesIgnoresUnsafeScanIDs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let scansRoot = root.appendingPathComponent("Scans")
        try FileManager.default.createDirectory(at: scansRoot, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 80).write(to: root.appendingPathComponent("escaped.usdz"))

        let measuring = RealAccountStorageMeasuring(
            scansRoot: scansRoot,
            sharedDirectories: []
        )
        let bytes = await measuring.usedBytes(forScanIDs: ["..", "", "foo/bar"])

        #expect(bytes == 0)
    }
}
