//
//  ViewerViewModelViewModeTests.swift
//  roomscanTests
//

import Foundation
import Observation
@testable import roomscan
import Testing

@MainActor
struct ViewerViewModelViewModeTests {
    @Test func setViewModeSameModeDoesNotNotifyObservers() async {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-mode-noop")
        viewModel.setViewMode(.topView)
        #expect(viewModel.viewMode == .topView)

        var didNotify = false
        withObservationTracking {
            _ = viewModel.viewMode
        } onChange: {
            didNotify = true
        }

        viewModel.setViewMode(.topView)

        #expect(viewModel.viewMode == .topView)
        #expect(!didNotify)
    }
}
