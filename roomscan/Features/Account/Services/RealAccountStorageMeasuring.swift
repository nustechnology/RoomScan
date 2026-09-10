//
//  RealAccountStorageMeasuring.swift
//  roomscan
//

import Foundation

/// Measures disk used by the current account's saved scan files (mesh and
/// thumbnails), plus app cache and in-progress capture drafts.
nonisolated struct RealAccountStorageMeasuring: AccountStorageMeasuring {
    let scansRoot: URL
    let sharedDirectories: [URL]

    init(
        scansRoot: URL = Self.defaultScansRoot,
        sharedDirectories: [URL] = Self.defaultSharedDirectories
    ) {
        self.scansRoot = scansRoot
        self.sharedDirectories = sharedDirectories
    }

    nonisolated func usedBytes(forScanIDs scanIDs: [String]) async -> Int64 {
        var total: Int64 = 0
        for scanID in Set(scanIDs) where Self.isSafeScanID(scanID) {
            total += Self.allocatedSize(of: scansRoot.appendingPathComponent(scanID, isDirectory: true))
        }
        for directory in sharedDirectories {
            total += Self.allocatedSize(of: directory)
        }
        return total
    }

    static let defaultScansRoot: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scans", isDirectory: true)
    }()

    static let defaultSharedDirectories: [URL] = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomScan", isDirectory: true)
        return [
            caches,
            support.appendingPathComponent("CaptureDrafts", isDirectory: true),
            support.appendingPathComponent("Drafts", isDirectory: true)
        ]
    }()

    private nonisolated static func isSafeScanID(_ scanID: String) -> Bool {
        guard !scanID.isEmpty, scanID != ".", scanID != ".." else { return false }
        return !scanID.contains("/") && !scanID.contains("\\")
    }

    private nonisolated static func allocatedSize(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
