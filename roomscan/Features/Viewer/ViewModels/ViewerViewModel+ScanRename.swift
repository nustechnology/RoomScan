//
//  ViewerViewModel+ScanRename.swift
//  roomscan
//

import Foundation

extension ViewerViewModel {
    func renameScan(to title: String) async -> ScanDetail? {
        guard allowsOwnerActions, !isBusy else { return nil }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            reportOperationError(String(localized: "viewer.scan.rename.error"))
            return nil
        }
        guard let modelDownloadService else {
            #if DEBUG
            print("rename unavailable reason=missing-scan-detail-service scanID=\(input.scanID)")
            #endif
            reportOperationError(String(localized: "viewer.scan.rename.error"))
            return nil
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let updatedDetail = try await modelDownloadService.updateScanDetail(
                id: input.scanID,
                name: trimmedTitle,
                description: nil
            )
            scanTitle = updatedDetail.name
            return updatedDetail
        } catch is CancellationError {
            return nil
        } catch {
            reportOperationError(String(localized: "viewer.scan.rename.error"))
            return nil
        }
    }
}
