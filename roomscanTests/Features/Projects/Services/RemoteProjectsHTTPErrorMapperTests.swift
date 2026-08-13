//
//  RemoteProjectsHTTPErrorMapperTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import Testing

struct RemoteProjectsHTTPErrorMapperTests {
    @Test func mapsProjectValidationForCreateProject() {
        let error = serverError(
            statusCode: 400,
            code: "VALIDATION"
        )

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .createProject)

        #expect(mapped == .invalidProjectName)
    }

    @Test func mapsScanValidationForCreateScan() {
        let error = serverError(
            statusCode: 400,
            code: "VALIDATION"
        )

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .createScan)

        #expect(mapped == .invalidScanName)
    }

    @Test func mapsDuplicateScanNameFromAPIErrorCode() {
        let error = serverError(
            statusCode: 409,
            code: "DUPLICATE_SCAN_NAME"
        )

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .createScan)

        #expect(mapped == .duplicateScanName)
    }

    @Test func mapsProjectNotFoundForProjectFetch() {
        let error = serverError(statusCode: 404, code: nil)

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .fetchProject)

        #expect(mapped == .projectNotFound)
    }

    @Test func mapsScanNotFoundForDeleteScan() {
        let error = serverError(statusCode: 404, code: nil)

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .deleteScan)

        #expect(mapped == .notFound)
    }

    @Test func mapsScanNotFoundForUploadSessionCreation() {
        let error = serverError(statusCode: 404, code: "SCAN_NOT_FOUND")

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .createAssetUploadSession)

        #expect(mapped == .notFound)
    }

    @Test func mapsFetchProjectsValidationToNetwork() {
        let error = serverError(statusCode: 400, code: "VALIDATION")

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .fetchProjects)

        #expect(mapped == .network)
    }

    @Test func mapsUploadSessionCompletionNotFoundToNetwork() {
        let error = serverError(statusCode: 404, code: nil)

        let mapped = RemoteProjectsHTTPErrorMapper.map(error, operation: .completeUploadSession)

        #expect(mapped == .network)
    }

    private func serverError(statusCode: Int, code: String?) -> HTTPClientError {
        let apiError = code.map {
            APIErrorResponse(
                error: APIErrorBody(code: $0, message: "Failure", details: nil),
                requestId: "req-1"
            )
        }
        return .serverError(statusCode: statusCode, apiError: apiError)
    }
}
