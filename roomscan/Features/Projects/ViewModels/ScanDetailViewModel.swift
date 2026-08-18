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

    private(set) var scan: RoomScanSummary
    private(set) var showsActionError = false
    private(set) var needsRescanForRetry = false
    private(set) var isPerformingAction = false
    private(set) var didDeleteScan = false
    private(set) var detail: ScanDetail?
    private(set) var isLoadingDetail = false

    var renameDraft = ""

    init(
        projectID: String,
        scan: RoomScanSummary,
        currentUserID: String,
        service: any ProjectsService,
        scanDetailService: (any ScanDetailService)? = nil,
        accessPolicy: DetailAccessPolicy = .editable
    ) {
        self.projectID = projectID
        self.scan = scan
        self.currentUserID = currentUserID
        self.service = service
        self.scanDetailService = scanDetailService
        self.accessPolicy = accessPolicy
        self.renameDraft = scan.name
    }

    var allowsOwnerActions: Bool {
        accessPolicy.allowsOwnerActions
    }

    var title: String {
        detail?.name ?? scan.name
    }

    var createdByText: String {
        let creatorID = detail?.creatorID ?? scan.creatorUserID
        if creatorID == currentUserID {
            return String(localized: "scanDetail.createdBy.you")
        }
        return detail?.creatorEmail ?? scan.creatorDisplayName
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
        String(detail?.noteCount ?? scan.notes.count)
    }

    var displaySyncStatus: RoomScanSyncStatus {
        detail?.syncStatus ?? scan.syncStatus
    }

    func loadDetail() async {
        guard let scanDetailService else { return }
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            detail = try await scanDetailService.fetchScanDetail(id: scan.id)
        } catch {
            return
        }
    }

    var showsRetryUpload: Bool {
        allowsOwnerActions && displaySyncStatus == .failed
    }

    var hasRemoteModelDownload: Bool {
        guard scanDetailService != nil else { return false }
        let assetStatus = detail?.assetStatus.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return assetStatus == "READY" || assetStatus == "UPLOADED"
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

    func beginRename() {
        guard allowsOwnerActions else { return }
        renameDraft = scan.name
    }

    @discardableResult
    func renameScan() async -> Bool {
        guard allowsOwnerActions else { return false }

        let trimmedName = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showsActionError = true
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            if let scanDetailService {
                let updatedDetail = try await scanDetailService.updateScanDetail(
                    id: scan.id,
                    name: trimmedName,
                    description: detail?.description
                )
                detail = updatedDetail
                scan = scanWithUpdatedName(updatedDetail.name)
            } else {
                scan = try await service.renameScan(
                    projectID: projectID,
                    scanID: scan.id,
                    name: trimmedName
                )
            }
            renameDraft = scan.name
            showsActionError = false
            return true
        } catch {
            showsActionError = true
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
        guard displaySyncStatus == .failed else { return false }

        isPerformingAction = true
        defer { isPerformingAction = false }

        needsRescanForRetry = false
        do {
            scan = try await service.retryScanUpload(
                projectID: projectID,
                scanID: scan.id
            )
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
            detail = detail?.updating(syncStatus: scan.syncStatus)
            needsRescanForRetry = false
            showsActionError = false
            return true
        } catch {
            showsActionError = true
            return false
        }
    }

    func dismissActionError() {
        showsActionError = false
    }

    private func scanWithUpdatedName(_ name: String) -> RoomScanSummary {
        RoomScanSummary(
            id: scan.id,
            name: name,
            createdAt: scan.createdAt,
            localModelURL: scan.localModelURL,
            thumbnailName: scan.thumbnailName,
            syncStatus: scan.syncStatus,
            creatorUserID: scan.creatorUserID,
            creatorDisplayName: scan.creatorDisplayName,
            notes: scan.notes,
            meshPath: scan.meshPath,
            thumbnailPath: scan.thumbnailPath
        )
    }

}
