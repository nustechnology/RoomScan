//
//  RealAccountStorageMeasuring.swift
//  roomscan
//

import Foundation

/// Measures the on-disk footprint of the app's local content: raw 3D mesh
/// files and thumbnails live in Documents, while app caches live in Caches.
struct RealAccountStorageMeasuring: AccountStorageMeasuring {
    let directories: [URL]

    init(directories: [URL] = Self.defaultDirectories) {
        self.directories = directories
    }

    nonisolated func usedBytes() async -> Int64 {
        var total: Int64 = 0
        for directory in directories {
            total += Self.allocatedSize(of: directory)
        }
        return total
    }

    static let defaultDirectories: [URL] = {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Application Support")
        ]
    }()

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
