//
//  RemoteSyncService.swift
//  roomscan
//

import Foundation

actor RemoteSyncService: SyncService {
    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchSyncStatus(projectId: String?) async throws -> [ProjectSyncStatusSummary] {
        var queryItems: [URLQueryItem] = []
        if let projectId, !projectId.isEmpty {
            queryItems.append(URLQueryItem(name: "projectId", value: projectId))
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/sync/status",
            method: .get,
            queryItems: queryItems
        )

        do {
            let response: SyncStatusAPIResponse = try await httpClient.request(endpoint)
            return response.items.map { $0.toSummary() }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch {
            throw SyncServiceError.network
        }
    }

    func fetchChanges(
        cursor: String?,
        since: Date?,
        limit: Int
    ) async throws -> SyncChangesPage {
        let clampedLimit = min(max(limit, 1), SyncEngine.maximumPageLimit)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(clampedLimit))
        ]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let since {
            queryItems.append(URLQueryItem(name: "since", value: Self.iso8601String(from: since)))
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/sync/changes",
            method: .get,
            queryItems: queryItems
        )

        do {
            let response: SyncChangesAPIResponse = try await httpClient.request(endpoint)
            #if DEBUG
            if response.skippedChangeCount > 0 {
                print(
                    "[RemoteSyncService] skipped \(response.skippedChangeCount) undecodable sync change(s)"
                )
            }
            #endif
            return SyncChangesPage(
                changes: response.changes.compactMap { $0.toDomain() },
                nextCursor: response.nextCursor
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw mapHTTPError(error)
        } catch {
            throw SyncServiceError.network
        }
    }

    private func mapHTTPError(_ error: HTTPClientError) -> SyncServiceError {
        switch error {
        case .networkError, .invalidURL:
            return .network
        case .serverError(let statusCode, _):
            switch statusCode {
            case 400:
                return .invalidRequest
            case 401:
                return .unauthorized
            case 404:
                return .notFound
            case 429:
                return .rateLimited
            default:
                return .server
            }
        case .decodingError:
            return .decoding
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
