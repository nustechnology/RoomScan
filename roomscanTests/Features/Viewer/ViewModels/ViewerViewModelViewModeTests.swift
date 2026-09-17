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

        // `onChange` is `@Sendable`; mutate via a reference box, not a captured `var`.
        let didNotify = NotifyFlag()
        withObservationTracking {
            _ = viewModel.viewMode
        } onChange: {
            didNotify.value = true
        }

        viewModel.setViewMode(.topView)

        #expect(viewModel.viewMode == .topView)
        #expect(!didNotify.value)
    }

    @Test func setViewModeDifferentModeUpdatesAndNotifiesObservers() async {
        let viewModel = await ViewerViewModelTestHelpers.loadedViewModel(scanID: "scan-mode-switch")
        #expect(viewModel.viewMode == .threeD)

        let didNotify = NotifyFlag()
        withObservationTracking {
            _ = viewModel.viewMode
        } onChange: {
            didNotify.value = true
        }

        viewModel.setViewMode(.topView)

        #expect(viewModel.viewMode == .topView)
        #expect(didNotify.value)
    }
}

/// Holds a mutable flag for `@Sendable` observation callbacks without capturing a local `var`.
private final class NotifyFlag: @unchecked Sendable {
    var value = false
}
