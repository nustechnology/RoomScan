//
//  ScanThumbnailLoader.swift
//  roomscan
//

import ImageIO
import SwiftUI

enum ScanThumbnailLoader {
    /// Reject oversized remote payloads before full decode.
    nonisolated private static let maxRemoteThumbnailBytes = 1_500_000

    nonisolated private static let thumbnailSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Loads and decodes off the caller's actor via a cancellable `Task.detached`
    /// (`nonisolated` alone does not move work under Approachable Concurrency).
    /// Parent cancellation is forwarded with `withTaskCancellationHandler`.
    nonisolated static func load(from thumbnailPath: String, maxPixelSize: Int) async -> UIImage? {
        guard !thumbnailPath.isEmpty else { return nil }

        if let remoteURL = URL(string: thumbnailPath),
           let scheme = remoteURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return await loadRemoteThumbnail(from: remoteURL, maxPixelSize: maxPixelSize)
        }

        let decodeTask = Task.detached(priority: .userInitiated) {
            loadLocalThumbnail(relativePath: thumbnailPath, maxPixelSize: maxPixelSize)
        }
        return await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }

    nonisolated private static func loadRemoteThumbnail(from url: URL, maxPixelSize: Int) async -> UIImage? {
        let work = Task.detached(priority: .userInitiated) { () -> UIImage? in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (bytes, response) = try await thumbnailSession.bytes(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    bytes.task.cancel()
                    return nil
                }

                let expectedLength = response.expectedContentLength
                if expectedLength > Int64(maxRemoteThumbnailBytes) {
                    bytes.task.cancel()
                    return nil
                }

                var data = Data()
                if expectedLength > 0 {
                    data.reserveCapacity(min(Int(expectedLength), maxRemoteThumbnailBytes))
                }

                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                    if data.count > maxRemoteThumbnailBytes {
                        bytes.task.cancel()
                        return nil
                    }
                }

                try Task.checkCancellation()
                return makeThumbnailImage(from: data as CFData, maxPixelSize: maxPixelSize)
            } catch is CancellationError {
                return nil
            } catch {
                return nil
            }
        }

        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    nonisolated private static func loadLocalThumbnail(
        relativePath: String,
        maxPixelSize: Int
    ) -> UIImage? {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsDir.appendingPathComponent(relativePath)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return makeThumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func makeThumbnailImage(from data: CFData, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        return makeThumbnailImage(from: source, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func makeThumbnailImage(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
