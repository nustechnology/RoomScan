//
//  LocalScanStorageService.swift
//  roomscan
//

import Foundation
import UIKit

struct DraftManifest: Codable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let meshPath: String
    let thumbnailPath: String
    let name: String
    let projectID: String?
}

protocol ScanStorageService: Sendable {
    func saveDraftManifest(_ draft: RoomScanDraft) throws
    func loadDraftManifest() -> RoomScanDraft?
    func clearDraftManifest()
    func persistSavedScan(draft: RoomScanDraft, scanID: String) throws -> (meshURL: URL, thumbnailURL: URL)
    func deleteScanFiles(scanID: String)
}

final class LocalScanStorageService: ScanStorageService, @unchecked Sendable {
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var cachesDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private var scansDirectory: URL {
        documentsDirectory.appendingPathComponent("Scans", isDirectory: true)
    }

    private var draftManifestURL: URL {
        cachesDirectory.appendingPathComponent("Drafts", isDirectory: true).appendingPathComponent("draft_manifest.json")
    }

    static func makeCaptureDraftDirectory(id: String = UUID().uuidString) throws -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = cachesDirectory
            .appendingPathComponent("RoomScan", isDirectory: true)
            .appendingPathComponent("CaptureDrafts", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    init() {
        try? fileManager.createDirectory(at: scansDirectory, withIntermediateDirectories: true)
        let draftDir = cachesDirectory.appendingPathComponent("Drafts", isDirectory: true)
        try? fileManager.createDirectory(at: draftDir, withIntermediateDirectories: true)
    }

    func saveDraftManifest(_ draft: RoomScanDraft) throws {
        let manifest = DraftManifest(
            id: draft.id,
            createdAt: draft.createdAt,
            meshPath: draft.meshFileURL.path,
            thumbnailPath: draft.thumbnailFileURL.path,
            name: draft.name,
            projectID: draft.projectID
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

            let meshURL = URL(fileURLWithPath: manifest.meshPath)
            let thumbURL = URL(fileURLWithPath: manifest.thumbnailPath)

            guard fileManager.fileExists(atPath: meshURL.path) else { return nil }

            return RoomScanDraft(
                id: manifest.id,
                createdAt: manifest.createdAt,
                meshFileURL: meshURL,
                thumbnailFileURL: thumbURL,
                name: manifest.name,
                projectID: manifest.projectID
            )
        } catch {
            return nil
        }
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
}
