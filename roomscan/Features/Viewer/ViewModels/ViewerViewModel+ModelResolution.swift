//
//  ViewerViewModel+ModelResolution.swift
//  roomscan
//

import Foundation

extension ViewerViewModel {
    /// Keeps the loading indicator visible for a short minimum duration on retry failures.
    /// - Returns: `true` when the delay finished normally; `false` if cancelled or skipped.
    @discardableResult
    func keepRetryLoadingVisibleIfNeeded(isRetry: Bool, startedAt: Date) async -> Bool {
        guard isRetry else { return true }
        let remainingDuration = 3 - Date().timeIntervalSince(startedAt)
        guard remainingDuration > 0 else { return true }
        do {
            try await Task.sleep(nanoseconds: UInt64(remainingDuration * 1_000_000_000))
            return true
        } catch is CancellationError {
            return false
        } catch {
            return false
        }
    }

    func resolveModelURL(forceDownload: Bool) async throws -> URL? {
        let destinationURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Scans", isDirectory: true)
        .appendingPathComponent(input.scanID, isDirectory: true)
        .appendingPathComponent("mesh.usdz")
        if !forceDownload || modelDownloadService == nil {
            if let modelURL = input.modelURL,
               FileManager.default.fileExists(atPath: modelURL.path) {
                return modelURL
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }
        guard let modelDownloadService else { return input.modelURL }
        try await modelDownloadService.downloadModel(scanID: input.scanID, to: destinationURL)
        return destinationURL
    }
}
