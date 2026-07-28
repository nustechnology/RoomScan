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
    private let currentUserID: String
    private let projectID: String

    private(set) var scan: RoomScanSummary
    private(set) var showsActionError = false
    private(set) var isPerformingAction = false
    private(set) var didDeleteScan = false

    var renameDraft = ""

    init(
        projectID: String,
        scan: RoomScanSummary,
        currentUserID: String,
        service: any ProjectsService
    ) {
        self.projectID = projectID
        self.scan = scan
        self.currentUserID = currentUserID
        self.service = service
        self.renameDraft = scan.name
    }

    var title: String {
        scan.name
    }

    var createdByText: String {
        if scan.creatorUserID == currentUserID {
            return String(localized: "scanDetail.createdBy.you")
        }
        return scan.creatorDisplayName
    }

    var formattedDate: String {
        Self.formattedDate(for: scan.createdAt)
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
        String(scan.notes.count)
    }

    var showsRetryUpload: Bool {
        scan.syncStatus == .failed
    }

    func beginRename() {
        renameDraft = scan.name
    }

    @discardableResult
    func renameScan() async -> Bool {
        let trimmedName = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showsActionError = true
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            scan = try await service.renameScan(
                projectID: projectID,
                scanID: scan.id,
                name: trimmedName
            )
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
        guard showsRetryUpload else { return false }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            scan = try await service.retryScanUpload(
                projectID: projectID,
                scanID: scan.id
            )
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
}
