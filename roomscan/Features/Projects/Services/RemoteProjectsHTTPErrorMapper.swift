//
//  RemoteProjectsHTTPErrorMapper.swift
//  roomscan
//

import Foundation

enum RemoteProjectsHTTPErrorMapper {
    enum Operation: Sendable {
        case fetchProjects
        case fetchProject
        case createProject
        case updateProject
        case deleteProject
        case deleteScan
        case createScan
        case createAssetUploadSession
        case completeUploadSession
    }

    static func map(_ error: HTTPClientError, operation: Operation) -> ProjectsServiceError {
        switch error {
        case .networkError, .invalidURL, .decodingError:
            return .network
        case .serverError(let statusCode, let apiError):
            if let mapped = mapAPIErrorCode(apiError?.error.code, operation: operation) {
                return mapped
            }
            return mapStatusCode(statusCode, operation: operation)
        }
    }

    private static func mapAPIErrorCode(
        _ code: String?,
        operation: Operation
    ) -> ProjectsServiceError? {
        guard let code else { return nil }

        switch code {
        case "PROJECT_NOT_FOUND":
            return .projectNotFound
        case "SCAN_NOT_FOUND":
            return .notFound
        case "DUPLICATE_SCAN_NAME":
            return .duplicateScanName
        case "INVALID_SCAN_NAME":
            return .invalidScanName
        case "INVALID_PROJECT_NAME":
            return .invalidProjectName
        case "VALIDATION", "VALIDATION_ERROR":
            return validationError(for: operation)
        case "NOT_FOUND":
            return notFoundError(for: operation)
        default:
            return nil
        }
    }

    private static func mapStatusCode(
        _ statusCode: Int,
        operation: Operation
    ) -> ProjectsServiceError {
        switch statusCode {
        case 400:
            return validationError(for: operation)
        case 404:
            return notFoundError(for: operation)
        default:
            return .network
        }
    }

    private static func validationError(for operation: Operation) -> ProjectsServiceError {
        switch operation {
        case .createProject, .updateProject:
            return .invalidProjectName
        case .createScan:
            return .invalidScanName
        case .fetchProjects, .fetchProject, .deleteProject, .deleteScan,
             .createAssetUploadSession, .completeUploadSession:
            return .network
        }
    }

    private static func notFoundError(for operation: Operation) -> ProjectsServiceError {
        switch operation {
        case .fetchProject, .updateProject, .deleteProject, .createScan:
            return .projectNotFound
        case .deleteScan, .createAssetUploadSession:
            return .notFound
        case .fetchProjects, .createProject, .completeUploadSession:
            return .network
        }
    }
}
