//
//  ScanDetailViewModel.swift
//  roomscan
//

import Foundation
import Observation

@MainActor
@Observable
final class ScanDetailViewModel {
    private let service: any ProjectsService
    /// Remote scan endpoints are optional until the backend contract provides them.
    private let scanDetailService: (any ScanDetailService)?
    private let currentUserID: String
    private let projectID: String
    private let accessPolicy: DetailAccessPolicy
    private let creatorDisplayNameFallback: String?

    private(set) var scan: RoomScanSummary
    private(set) var showsActionError = false
    private(set) var actionErrorMessage: String?
    private(set) var needsRescanForRetry = false
    private(set) var isPerformingAction = false
    private(set) var didDeleteScan = false
    private(set) var detail: ScanDetail?
    private(set) var isLoadingDetail = false
    /// Bumped on every detail fetch so only the newest in-flight response can update state.
    private var detailLoadGeneration = 0
    /// Set when a silent refresh is requested while a visible load is still in flight.
    private var needsSilentDetailRefresh = false

    var renameDraft = ""

    init(
        projectID: String,
        scan: RoomScanSummary,
        currentUserID: String,
        service: any ProjectsService,
        scanDetailService: (any ScanDetailService)? = nil,
        accessPolicy: DetailAccessPolicy = .editable,
        creatorDisplayNameFallback: String? = nil
    ) {
        self.projectID = projectID
        self.scan = scan
        self.currentUserID = currentUserID
        self.service = service
        self.scanDetailService = scanDetailService
        self.accessPolicy = accessPolicy
        self.creatorDisplayNameFallback = creatorDisplayNameFallback
        self.renameDraft = scan.name
    }

    var allowsOwnerActions: Bool {
        accessPolicy.allowsOwnerActions
    }

    var title: String {
        detail?.name ?? scan.name
    }

    var thumbnailPath: String {
        for candidate in [detail?.thumbnail, scan.thumbnailPath] {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return ""
    }

    var createdByText: String {
        let creatorID = detail?.creatorID ?? scan.creatorUserID
        if creatorID == currentUserID {
            return String(localized: "scanDetail.createdBy.you")
        }

        for value in [
            detail?.creatorDisplayName,
            scan.creatorDisplayName,
            detail?.creatorEmail,
            creatorDisplayNameFallback
        ] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return String(localized: "shared.owner.unknown")
    }

    var formattedDate: String {
        Self.formattedDate(for: detail?.createdAt ?? scan.createdAt)
    }

    static func formattedDate(
        for date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var style = Date.FormatStyle()
            .month(.abbreviated)
            .day()
            .year()
            .locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    var notesCountText: String {
        String(detail?.noteCount ?? scan.noteCount)
    }

    var displaySyncStatus: RoomScanSyncStatus {
        guard let detail else { return scan.syncStatus }
        return ProjectAPIMapping.preferredSyncStatus(
            local: scan.syncStatus,
            remote: detail.syncStatus,
            hasLocalUploadArtifacts: scan.hasLocalUploadArtifacts
        )
    }

    var canShare: Bool {
        RoomScanSummary.isReadyToShare(
            syncStatus: displaySyncStatus,
            assetStatus: shareAssetStatus
        )
    }

    var shareAssetStatus: String? {
        detail?.assetStatus ?? scan.assetStatus
    }

    func loadDetail(showsLoadingIndicator: Bool = true) async {
        guard let scanDetailService else { return }
        guard !isLoadingDetail else {
            if !showsLoadingIndicator {
                needsSilentDetailRefresh = true
            }
            return
        }
        if showsLoadingIndicator {
            isLoadingDetail = true
        }

        detailLoadGeneration += 1
        let loadGeneration = detailLoadGeneration

        do {
            let fetched = try await scanDetailService.fetchScanDetail(id: scan.id)
            guard loadGeneration == detailLoadGeneration else {
                await finishDetailLoad(showsLoadingIndicator: showsLoadingIndicator)
                return
            }
            let mergedStatus = ProjectAPIMapping.preferredSyncStatus(
                local: scan.syncStatus,
                remote: fetched.syncStatus,
                hasLocalUploadArtifacts: scan.hasLocalUploadArtifacts
            )
            detail = fetched.updating(syncStatus: mergedStatus)
            scan = scanReplacing(
                syncStatus: mergedStatus,
                noteCount: fetched.noteCount
            )
        } catch {
            // Keep list-row scan metadata when detail fetch fails.
        }

        await finishDetailLoad(showsLoadingIndicator: showsLoadingIndicator)
    }

    private func finishDetailLoad(showsLoadingIndicator: Bool) async {
        if showsLoadingIndicator {
            isLoadingDetail = false
        }
        guard needsSilentDetailRefresh else { return }
        needsSilentDetailRefresh = false
        await loadDetail(showsLoadingIndicator: false)
    }

    var showsRetryUpload: Bool {
        allowsOwnerActions && (displaySyncStatus == .failed || displaySyncStatus == .conflict)
    }

    var hasRemoteModelDownload: Bool {
        guard scanDetailService != nil else { return false }
        return RoomScanSummary.isRemoteAssetUploaded(detail?.assetStatus)
    }

    var canOpen3DModel: Bool {
        scan.localModelURL != nil || hasRemoteModelDownload
    }

    var modelDownloadService: (any ScanDetailService)? {
        scanDetailService
    }

    var viewerModelVersion: String? {
        detail.map { String($0.modelVersion) }
    }

    @discardableResult
    func renameScan() async -> Bool {
        guard allowsOwnerActions else { return false }

        let trimmedName = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            presentActionError()
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            if await hasDuplicateScanName(trimmedName) {
                presentActionError(message: String(localized: "review.error.duplicate_name"))
                return false
            }
            if let scanDetailService {
                let updatedDetail = try await scanDetailService.updateScanDetail(
                    id: scan.id,
                    name: trimmedName,
                    description: detail?.description
                )
                invalidateInFlightDetailLoads()
                detail = updatedDetail
                scan = scanWithUpdatedName(updatedDetail.name)
            } else {
                scan = try await service.renameScan(
                    projectID: projectID,
                    scanID: scan.id,
                    name: trimmedName
                )
                invalidateInFlightDetailLoads()
            }
            renameDraft = scan.name
            dismissActionError()
            return true
        } catch let error as HTTPClientError {
            presentActionError(message: actionErrorMessage(for: error))
            return false
        } catch {
            presentActionError()
            return false
        }
    }

    @discardableResult
    func deleteScan() async -> Bool {
        guard allowsOwnerActions else { return false }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await service.deleteScan(projectID: projectID, scanID: scan.id)
            invalidateInFlightDetailLoads()
            didDeleteScan = true
            showsActionError = false
            return true
        } catch {
            showsActionError = true
            return false
        }
    }

    @discardableResult
    func retryUpload() async -> Bool {
        guard allowsOwnerActions else { return false }
        guard displaySyncStatus == .failed || displaySyncStatus == .conflict else { return false }

        isPerformingAction = true
        defer { isPerformingAction = false }

        needsRescanForRetry = false
        do {
            scan = try await service.retryScanUpload(
                projectID: projectID,
                scanID: scan.id
            )
            invalidateInFlightDetailLoads()
            detail = detail?.updating(syncStatus: scan.syncStatus)
            showsActionError = false
            return true
        } catch ProjectsServiceError.notFound {
            needsRescanForRetry = true
            showsActionError = false
            return false
        } catch {
            showsActionError = true
            return false
        }
    }

    @discardableResult
    func retryUpload(with draft: RoomScanDraft) async -> Bool {
        guard allowsOwnerActions else { return false }
        guard let retryService = service as? any ScanAssetRetrying else {
            showsActionError = true
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            scan = try await retryService.retryScanUpload(
                projectID: projectID,
                scanID: scan.id,
                meshURL: draft.meshFileURL,
                thumbnailURL: draft.thumbnailFileURL
            )
            invalidateInFlightDetailLoads()
            detail = detail?.updating(syncStatus: scan.syncStatus)
            needsRescanForRetry = false
            showsActionError = false
            return true
        } catch {
            showsActionError = true
            return false
        }
    }

    /// Bumps the shared generation so any in-flight `loadDetail` response is ignored.
    private func invalidateInFlightDetailLoads() {
        detailLoadGeneration += 1
    }

    private func scanWithUpdatedName(_ name: String) -> RoomScanSummary {
        scanReplacing(name: name)
    }

    private func scanReplacing(
        name: String? = nil,
        syncStatus: RoomScanSyncStatus? = nil,
        noteCount: Int? = nil
    ) -> RoomScanSummary {
        RoomScanSummary(
            id: scan.id,
            name: name ?? scan.name,
            createdAt: scan.createdAt,
            localModelURL: scan.localModelURL,
            thumbnailName: scan.thumbnailName,
            syncStatus: syncStatus ?? scan.syncStatus,
            creatorUserID: scan.creatorUserID,
            creatorDisplayName: scan.creatorDisplayName,
            notes: scan.notes,
            meshPath: scan.meshPath,
            thumbnailPath: scan.thumbnailPath,
            noteCount: noteCount ?? scan.noteCount,
            assetStatus: scan.assetStatus
        )
    }

}

extension ScanDetailViewModel {
    func beginRename() {
        guard allowsOwnerActions else { return }
        renameDraft = scan.name
    }

    func applyViewerRename(_ updatedDetail: ScanDetail) {
        invalidateInFlightDetailLoads()
        detail = updatedDetail
        scan = scanWithUpdatedName(updatedDetail.name)
    }

    func dismissActionError() {
        showsActionError = false
        actionErrorMessage = nil
    }

    private func hasDuplicateScanName(_ name: String) async -> Bool {
        let currentName = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentName.caseInsensitiveCompare(name) != .orderedSame else { return false }
        return (try? await service.isScanNameDuplicate(name: name, projectID: projectID)) ?? false
    }

    private func presentActionError(message: String? = nil) {
        actionErrorMessage = message
        showsActionError = true
    }

    private func actionErrorMessage(for error: HTTPClientError) -> String? {
        guard case .serverError(409, _) = error else { return nil }
        return String(localized: "review.error.duplicate_name")
    }
}
