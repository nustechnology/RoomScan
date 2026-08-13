//
//  RoomScanDraft.swift
//  roomscan
//

import Foundation

struct RoomScanDraft: Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let meshFileURL: URL
    let thumbnailFileURL: URL
    var name: String
    var projectID: String?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        meshFileURL: URL,
        thumbnailFileURL: URL,
        name: String = "",
        projectID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.meshFileURL = meshFileURL
        self.thumbnailFileURL = thumbnailFileURL
        self.name = name
        self.projectID = projectID
    }

    /// Removes only files created inside the app's writable storage. Development
    /// fixtures may reference files outside the sandbox and must never be deleted.
    func deleteManagedFiles(fileManager: FileManager = .default) {
        let managedDirectories = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0],
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        ].map(\.standardizedFileURL)

        for fileURL in [meshFileURL, thumbnailFileURL] {
            let path = fileURL.standardizedFileURL.path
            guard managedDirectories.contains(where: { directory in
                path.hasPrefix(directory.path + "/")
            }) else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
