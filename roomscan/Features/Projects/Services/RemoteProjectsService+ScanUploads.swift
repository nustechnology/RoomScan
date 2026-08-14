//
//  RemoteProjectsService+ScanUploads.swift
//  roomscan
//

import CryptoKit
import Foundation

extension RemoteProjectsService {
    func saveScan(
        draft: RoomScanDraft,
        name: String,
        projectID: String,
        meshURL: URL
    ) async throws -> RoomScanSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...50).contains(trimmedName.count) else {
            throw ProjectsServiceError.invalidScanName
        }

        let assets = try readScanAssets(draft: draft, meshURL: meshURL)
        let response = try await createScan(
            name: trimmedName,
            projectID: projectID,
            assets: assets
        )
        do {
            try await uploadScanAssets(response.uploads, assets: assets)
            let savedScan = try await persistCreatedScan(
                response.id,
                draft: draft,
                name: trimmedName,
                projectID: projectID,
                meshURL: meshURL
            )
            _ = try? await fetchProject(id: projectID)
            return savedScan
        } catch {
            try? await deleteScan(projectID: projectID, scanID: response.id)
            throw error
        }
    }

    func retryScanUpload(projectID: String, scanID: String) async throws -> RoomScanSummary {
        let project = try await localStore.fetchProject(id: projectID)
        guard let scan = project.roomScans.first(where: { $0.id == scanID }) else {
            throw ProjectsServiceError.notFound
        }
        return try await retryScanUpload(
            projectID: projectID,
            scanID: scanID,
            assets: try readRetryAssets(scan)
        )
    }

    func retryScanUpload(
        projectID: String,
        scanID: String,
        meshURL: URL,
        thumbnailURL: URL
    ) async throws -> RoomScanSummary {
        do {
            let assets = (
                thumbnail: try Data(contentsOf: thumbnailURL),
                mesh: try Data(contentsOf: meshURL)
            )
            return try await retryScanUpload(projectID: projectID, scanID: scanID, assets: assets)
        } catch let error as ProjectsServiceError {
            throw error
        } catch {
            throw ProjectsServiceError.notFound
        }
    }

    func mapHTTPClientError(_ error: HTTPClientError) -> ProjectsServiceError {
        switch error {
        case .networkError, .invalidURL, .decodingError:
            return .network
        case .serverError(let statusCode, _):
            switch statusCode {
            case 400:
                return .invalidProjectName
            case 404:
                return .projectNotFound
            default:
                return .network
            }
        }
    }

    #if DEBUG
    func logHTTPClientError(_ operation: String, _ error: HTTPClientError) {
        print("[RemoteProjectsService] \(operation) failed: \(error)")
    }
    #endif
}

private extension RemoteProjectsService {
    func retryScanUpload(
        projectID: String,
        scanID: String,
        assets: (thumbnail: Data, mesh: Data)
    ) async throws -> RoomScanSummary {
        let uploads = try await createRetryUploadSessions(scanID: scanID, assets: assets)
        try await uploadScanAssets(uploads, assets: assets)
        _ = try await localStore.retryScanUpload(projectID: projectID, scanID: scanID)
        let refreshedProject = try await fetchProject(id: projectID)
        guard let refreshedScan = refreshedProject.roomScans.first(where: { $0.id == scanID }) else {
            throw ProjectsServiceError.notFound
        }
        return refreshedScan
    }

    func readScanAssets(draft: RoomScanDraft, meshURL: URL) throws -> (thumbnail: Data, mesh: Data) {
        do {
            return (
                thumbnail: try Data(contentsOf: draft.thumbnailFileURL),
                mesh: try Data(contentsOf: meshURL)
            )
        } catch {
            throw ProjectsServiceError.network
        }
    }

    func readRetryAssets(_ scan: RoomScanSummary) throws -> (thumbnail: Data, mesh: Data) {
        guard let meshURL = scan.localModelURL else {
            throw ProjectsServiceError.notFound
        }
        let thumbnailFilename = scan.thumbnailName.isEmpty ? "thumbnail.jpg" : scan.thumbnailName
        let thumbnailURL = meshURL.deletingLastPathComponent().appendingPathComponent(thumbnailFilename)
        do {
            return (
                thumbnail: try Data(contentsOf: thumbnailURL),
                mesh: try Data(contentsOf: meshURL)
            )
        } catch {
            throw ProjectsServiceError.notFound
        }
    }

    func createRetryUploadSessions(
        scanID: String,
        assets: (thumbnail: Data, mesh: Data)
    ) async throws -> ScanUploadURLs {
        let modelRequest = CreateAssetUploadSessionAPIRequest(
            assetType: "MODEL",
            contentType: "model/usdz",
            sizeBytes: assets.mesh.count,
            checksum: Self.sha256(for: assets.mesh),
            modelVersion: "1.0"
        )
        let thumbnailRequest = CreateAssetUploadSessionAPIRequest(
            assetType: "THUMBNAIL",
            contentType: "image/jpeg",
            sizeBytes: assets.thumbnail.count,
            checksum: nil,
            modelVersion: nil
        )
        let scanFile = try await createAssetUploadSession(scanID: scanID, request: modelRequest)
        let thumbnail: PresignedUploadTarget
        do {
            thumbnail = try await createAssetUploadSession(scanID: scanID, request: thumbnailRequest)
        } catch {
            await reportUploadFailure(scanFile)
            throw error
        }
        return ScanUploadURLs(thumbnail: thumbnail, scanFile: scanFile)
    }

    func createAssetUploadSession(
        scanID: String,
        request: CreateAssetUploadSessionAPIRequest
    ) async throws -> PresignedUploadTarget {
        do {
            let body = try JSONEncoder().encode(request)
            return try await httpClient.request(
                APIEndpoint(
                    path: "/api/v1/scans/\(scanID)/assets/upload-sessions",
                    method: .post,
                    body: body
                )
            )
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw ProjectsServiceError.network
        }
    }

    func createScan(
        name: String,
        projectID: String,
        assets: (thumbnail: Data, mesh: Data)
    ) async throws -> CreateScanAPIResponse {
        let request = CreateScanAPIRequest(
            name: name,
            thumbnail: ScanAssetMetadataRequest(
                contentType: "image/jpeg", sizeBytes: assets.thumbnail.count, checksum: nil, modelVersion: nil
            ),
            scanFile: ScanAssetMetadataRequest(
                contentType: "model/usdz", sizeBytes: assets.mesh.count,
                checksum: Self.sha256(for: assets.mesh), modelVersion: "1.0"
            )
        )
        do {
            let body = try JSONEncoder().encode(request)
            return try await httpClient.request(
                APIEndpoint(path: "/api/v1/projects/\(projectID)/scans", method: .post, body: body)
            )
        } catch let error as HTTPClientError {
            throw mapHTTPClientError(error)
        } catch {
            throw ProjectsServiceError.network
        }
    }

    func persistCreatedScan(
        _ scanID: String,
        draft: RoomScanDraft,
        name: String,
        projectID: String,
        meshURL: URL
    ) async throws -> RoomScanSummary {
        let remoteDraft = RoomScanDraft(
            id: scanID, createdAt: draft.createdAt, meshFileURL: meshURL,
            thumbnailFileURL: draft.thumbnailFileURL, name: name, projectID: projectID
        )
        return try await localStore.saveScan(
            draft: remoteDraft, name: name, projectID: projectID, meshURL: meshURL
        )
    }

    func uploadScanAssets(
        _ uploads: ScanUploadURLs,
        assets: (thumbnail: Data, mesh: Data)
    ) async throws {
        async let thumbnailUpload: Void = uploadAndComplete(
            assets.thumbnail, contentType: "image/jpeg", target: uploads.thumbnail
        )
        async let meshUpload: Void = uploadAndComplete(
            assets.mesh, contentType: "model/usdz", target: uploads.scanFile
        )
        _ = try await (thumbnailUpload, meshUpload)
    }

    func uploadAndComplete(
        _ data: Data,
        contentType: String,
        target: PresignedUploadTarget
    ) async throws {
        do {
            var request = URLRequest(url: target.uploadUrl)
            request.httpMethod = HTTPMethod.put.rawValue
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            let (_, response) = try await uploadSession.data(for: request)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw ProjectsServiceError.network
            }
            let completion = UploadCompletionAPIRequest(
                sizeBytes: data.count,
                checksum: contentType == "model/usdz" ? Self.sha256(for: data) : nil
            )
            let body = try JSONEncoder().encode(completion)
            let _: EmptyAPIResponse = try await httpClient.request(
                APIEndpoint(path: "/api/v1/upload-sessions/\(target.uploadSessionId)/complete", method: .post, body: body)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !Task.isCancelled else { throw CancellationError() }
            await reportUploadFailure(target)
            throw ProjectsServiceError.network
        }
    }

    func reportUploadFailure(_ target: PresignedUploadTarget) async {
        guard let body = try? JSONEncoder().encode(UploadFailureAPIRequest(
            reason: "Client-side asset upload failed"
        )) else { return }
        let _: EmptyAPIResponse? = try? await httpClient.request(
            APIEndpoint(path: "/api/v1/upload-sessions/\(target.uploadSessionId)/fail", method: .post, body: body)
        )
    }

    static func sha256(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
