//
//  ScanDetailView+ViewerRename.swift
//  roomscan
//

import SwiftUI

extension ScanDetailView {
    @MainActor
    func applyViewerRename(_ detail: ScanDetail) {
        viewModel.applyViewerRename(detail)
        onScanUpdated(viewModel.scan)
    }
}
