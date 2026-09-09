//
//  LocalScanStorageService.swift
//  roomscan
//

import Foundation
import UIKit

nonisolated struct DraftManifest: Codable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let meshPath: String
    let thumbnailPath: String
    let name: String
    let projectID: String?
    let createScanIdempotencyKey: String?
    var createScanRequestName: String?
    var createScanRequestProjectID: String?

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, meshPath, thumbnailPath, name, projectID
        case createScanIdempotencyKey, createScanRequestName, createScanRequestProjectID
    }

    init(
        id: String,
        createdAt: Date,
        meshPath: String,
        thumbnailPath: String,
        name: String,
        projectID: String?,
        createScanIdempotencyKey: String?,
        createScanRequestName: String?,
        createScanRequestProjectID: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.meshPath = meshPath
        self.thumbnailPath = thumbnailPath
        self.name = name
        self.projectID = projectID
        self.createScanIdempotencyKey = createScanIdempotencyKey
        self.createScanRequestName = createScanRequestName
        self.createScanRequestProjectID = createScanRequestProjectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        meshPath = try container.decode(String.self, forKey: .meshPath)
        thumbnailPath = try container.decode(String.self, forKey: .thumbnailPath)
        name = try container.decode(String.self, forKey: .name)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        createScanIdempotencyKey = try container.decodeIfPresent(String.self, forKey: .createScanIdempotencyKey)
        createScanRequestName = try container.decodeIfPresent(String.self, forKey: .createScanRequestName)
        createScanRequestProjectID = try container.decodeIfPresent(String.self, forKey: .createScanRequestProjectID)
    }
}

nonisolated protocol ScanStorageService: Sendable {
    func saveDraftManifest(_ draft: RoomScanDraft) throws
    func loadDraftManifest() -> RoomScanDraft?
    func clearDraftManifest()
    func persistSavedScan(draft: RoomScanDraft, scanID: String) throws -> (meshURL: URL, thumbnailURL: URL)
    func deleteScanFiles(scanID: String)
    func meshExists(scanID: String) -> Bool
    /// Returns the subset of `candidates` that have a local `mesh.usdz` on disk.
    /// Prefer this over repeated `meshExists` calls. Implementations should offload
    /// filesystem work (e.g. via `Task.detached`); `nonisolated` alone does not.
    func existingMeshScanIDs(in candidates: [String]) async -> Set<String>
}

extension ScanStorageService {
    nonisolated func meshExists(scanID: String) -> Bool { false }
    nonisolated func existingMeshScanIDs(in candidates: [String]) async -> Set<String> { [] }
}

nonisolated final class LocalScanStorageService: ScanStorageService, @unchecked Sendable {
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var cachesDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private var scansDirectory: URL {
        documentsDirectory.appendingPathComponent("Scans", isDirectory: true)
    }

    /// Durable root for recoverable draft data (manifest, mesh, thumbnail).
    private var draftsRootDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("RoomScan", isDirectory: true)
    }

    private var draftManifestDirectory: URL {
        draftsRootDirectory.appendingPathComponent("Drafts", isDirectory: true)
    }

    private var draftManifestURL: URL {
        draftManifestDirectory.appendingPathComponent("draft_manifest.json")
    }

    private var captureDraftsDirectory: URL {
        draftsRootDirectory.appendingPathComponent("CaptureDrafts", isDirectory: true)
    }

    static func makeCaptureDraftDirectory(id: String = UUID().uuidString) throws -> URL {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let draftsRoot = supportDirectory.appendingPathComponent("RoomScan", isDirectory: true)
        try Self.ensureDirectoryExistsAndExcludeFromBackup(draftsRoot, fileManager: fileManager)

        let directory = draftsRoot
            .appendingPathComponent("CaptureDrafts", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    init() {
        try? fileManager.createDirectory(at: scansDirectory, withIntermediateDirectories: true)
        try? Self.ensureDirectoryExistsAndExcludeFromBackup(draftsRootDirectory, fileManager: fileManager)
        try? fileManager.createDirectory(at: draftManifestDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: captureDraftsDirectory, withIntermediateDirectories: true)
        migrateDraftDataFromCachesIfNeeded()
    }

    func saveDraftManifest(_ draft: RoomScanDraft) throws {
        let manifest = DraftManifest(
            id: draft.id,
            createdAt: draft.createdAt,
            meshPath: relativePath(for: draft.meshFileURL, relativeTo: applicationSupportDirectory),
            thumbnailPath: relativePath(for: draft.thumbnailFileURL, relativeTo: applicationSupportDirectory),
            name: draft.name,
            projectID: draft.projectID,
            createScanIdempotencyKey: draft.createScanIdempotencyKey,
            createScanRequestName: draft.createScanRequestName,
            createScanRequestProjectID: draft.createScanRequestProjectID
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: draftManifestURL, options: .atomic)
    }

    func loadDraftManifest() -> RoomScanDraft? {
        guard fileManager.fileExists(atPath: draftManifestURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: draftManifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(DraftManifest.self, from: data)

            let meshURL = resolvedURL(forStoredPath: manifest.meshPath, relativeTo: applicationSupportDirectory)
            let thumbURL = resolvedURL(forStoredPath: manifest.thumbnailPath, relativeTo: applicationSupportDirectory)

            guard fileManager.fileExists(atPath: meshURL.path) else { return nil }

            return RoomScanDraft(
                id: manifest.id,
                createdAt: manifest.createdAt,
                meshFileURL: meshURL,
                thumbnailFileURL: thumbURL,
                name: manifest.name,
                projectID: manifest.projectID,
                createScanIdempotencyKey: manifest.createScanIdempotencyKey,
                createScanRequestName: manifest.createScanRequestName,
                createScanRequestProjectID: manifest.createScanRequestProjectID
            )
        } catch {
            return nil
        }
    }

    private func relativePath(for fileURL: URL, relativeTo baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath == basePath || filePath.hasPrefix(basePath + "/") else {
            return filePath
        }
        var relative = String(filePath.dropFirst(basePath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }

    private func resolvedURL(forStoredPath storedPath: String, relativeTo baseURL: URL) -> URL {
        if !storedPath.hasPrefix("/") {
            let candidate = baseURL.appendingPathComponent(storedPath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            // Legacy relative path written against the caches directory.
            let legacyCachesCandidate = cachesDirectory.appendingPathComponent(storedPath)
            if fileManager.fileExists(atPath: legacyCachesCandidate.path) {
                return legacyCachesCandidate
            }

            return candidate
        }

        // Absolute path: reuse if still valid, otherwise rebase under Application Support
        // (and fall back to the caches root for pre-migration drafts).
        if fileManager.fileExists(atPath: storedPath) {
            return URL(fileURLWithPath: storedPath)
        }

        let supportMarker = "/Library/Application Support/"
        if let range = storedPath.range(of: supportMarker) {
            let relative = String(storedPath[range.upperBound...])
            return baseURL.appendingPathComponent(relative)
        }

        let cachesMarker = "/Library/Caches/"
        if let range = storedPath.range(of: cachesMarker) {
            let relative = String(storedPath[range.upperBound...])
            let supportCandidate = applicationSupportDirectory.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: supportCandidate.path) {
                return supportCandidate
            }
            return cachesDirectory.appendingPathComponent(relative)
        }

        return URL(fileURLWithPath: storedPath)
    }

    func clearDraftManifest() {
        try? fileManager.removeItem(at: draftManifestURL)
    }

    func persistSavedScan(draft: RoomScanDraft, scanID: String) throws -> (meshURL: URL, thumbnailURL: URL) {
        let targetDir = scansDirectory.appendingPathComponent(scanID, isDirectory: true)
        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let targetMeshURL = targetDir.appendingPathComponent("mesh.usdz")
        let targetThumbURL = targetDir.appendingPathComponent("thumbnail.jpg")

        if fileManager.fileExists(atPath: targetMeshURL.path) {
            try? fileManager.removeItem(at: targetMeshURL)
        }
        if fileManager.fileExists(atPath: targetThumbURL.path) {
            try? fileManager.removeItem(at: targetThumbURL)
        }

        try fileManager.copyItem(at: draft.meshFileURL, to: targetMeshURL)
        if fileManager.fileExists(atPath: draft.thumbnailFileURL.path) {
            try fileManager.copyItem(at: draft.thumbnailFileURL, to: targetThumbURL)
        } else {
            let jpegData = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480))
                .jpegData(withCompressionQuality: 0.82) { context in
                    UIColor.systemGray5.setFill()
                    context.cgContext.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
                }
            try jpegData.write(to: targetThumbURL, options: .atomic)
        }

        return (meshURL: targetMeshURL, thumbnailURL: targetThumbURL)
    }

    func deleteScanFiles(scanID: String) {
        let targetDir = scansDirectory.appendingPathComponent(scanID, isDirectory: true)
        try? fileManager.removeItem(at: targetDir)
    }

    func meshExists(scanID: String) -> Bool {
        guard isSafeScanID(scanID) else { return false }
        let meshURL = scansDirectory
            .appendingPathComponent(scanID, isDirectory: true)
            .appendingPathComponent("mesh.usdz")
        return fileManager.fileExists(atPath: meshURL.path)
    }

    nonisolated func existingMeshScanIDs(in candidates: [String]) async -> Set<String> {
        let safeCandidates = Set(candidates.filter(isSafeScanID))
        guard !safeCandidates.isEmpty else { return [] }

        let scansDirectory = self.scansDirectory
        let fileManager = self.fileManager
        return await Task.detached(priority: .utility) {
            let present = Set((try? fileManager.contentsOfDirectory(atPath: scansDirectory.path)) ?? [])
            let matchingDirectories = safeCandidates.intersection(present)
            guard !matchingDirectories.isEmpty else { return [] }

            return matchingDirectories.filter { scanID in
                let meshURL = scansDirectory
                    .appendingPathComponent(scanID, isDirectory: true)
                    .appendingPathComponent("mesh.usdz")
                return fileManager.fileExists(atPath: meshURL.path)
            }
        }.value
    }

    private nonisolated func isSafeScanID(_ scanID: String) -> Bool {
        guard !scanID.isEmpty, scanID != ".", scanID != ".." else { return false }
        return !scanID.contains("/") && !scanID.contains("\\")
    }

    // MARK: - Private helpers

    private static func ensureDirectoryExistsAndExcludeFromBackup(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
    }

    /// Moves recoverable draft data that previously lived under Caches into Application Support.
    private func migrateDraftDataFromCachesIfNeeded() {
        let legacyManifestURL = cachesDirectory
            .appendingPathComponent("Drafts", isDirectory: true)
            .appendingPathComponent("draft_manifest.json")
        if fileManager.fileExists(atPath: legacyManifestURL.path),
           !fileManager.fileExists(atPath: draftManifestURL.path) {
            try? fileManager.createDirectory(at: draftManifestDirectory, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: legacyManifestURL, to: draftManifestURL)
        }

        let legacyCaptureDrafts = cachesDirectory
            .appendingPathComponent("RoomScan", isDirectory: true)
            .appendingPathComponent("CaptureDrafts", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyCaptureDrafts.path) else { return }

        let children = (try? fileManager.contentsOfDirectory(
            at: legacyCaptureDrafts,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in children {
            let destination = captureDraftsDirectory.appendingPathComponent(child.lastPathComponent, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: child)
            } else {
                try? fileManager.moveItem(at: child, to: destination)
            }
        }

        try? fileManager.removeItem(at: legacyCaptureDrafts)
    }
}
