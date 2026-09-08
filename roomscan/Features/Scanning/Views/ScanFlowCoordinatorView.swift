//
//  ScanFlowCoordinatorView.swift
//  roomscan
//

import Foundation
import SwiftUI

enum ScanFlowStep: Equatable {
    case readiness
    case camera
    case review(RoomScanDraft)
}

struct ScanFlowCoordinatorView: View {
    let sourceProjectID: String?
    let projectsService: ProjectsService
    let onComplete: (RoomScanSummary?) -> Void
    let onCancel: () -> Void

    @State private var step: ScanFlowStep
    @State private var prewarmedService: RoomCaptureService

    init(
        sourceProjectID: String? = nil,
        recoveredDraft: RoomScanDraft? = nil,
        projectsService: ProjectsService,
        onComplete: @escaping (RoomScanSummary?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceProjectID = sourceProjectID
        self.projectsService = projectsService
        self.onComplete = onComplete
        self.onCancel = onCancel
        let bypassReadiness = ProcessInfo.processInfo.arguments.contains("-SkipScanReadiness")
        let initialStep = ScanFlowStep.initialStep(
            for: recoveredDraft,
            bypassingReadiness: bypassReadiness
        )
        _step = State(initialValue: initialStep)
        _prewarmedService = State(initialValue: RoomCaptureServiceFactory.makeService())
    }

    var body: some View {
        Group {
            switch step {
            case .readiness:
                NavigationStack {
                    ScanCheckView(
                        viewModel: ScanCheckViewModel(sourceProjectID: sourceProjectID),
                        onStartScan: {
                            ScanTelemetry.shared.recordStartScanTapped()
                            ScanTelemetry.shared.recordPreScanTransitionBegan()
                            step = .camera
                        },
                        onCancel: {
                            onCancel()
                        }
                    )
                }

            case .camera:
                CameraScanView(
                    sourceProjectID: sourceProjectID,
                    captureService: prewarmedService,
                    onFinish: { draft in
                        step = .review(draft)
                    },
                    onCancel: {
                        onCancel()
                    }
                )

            case .review(let draft):
                ReviewScanView(
                    draft: draft,
                    preselectedProjectID: sourceProjectID,
                    projectsService: projectsService,
                    onSaveSuccess: { savedScan in
                        onComplete(savedScan)
                    },
                    onScanAgain: {
                        ScanTelemetry.shared.recordStartScanTapped()
                        step = .camera
                    },
                    onDiscard: {
                        onCancel()
                    }
                )
            }
        }
    }
}

extension ScanFlowStep {
    static func initialStep(
        for recoveredDraft: RoomScanDraft?,
        bypassingReadiness: Bool = false
    ) -> ScanFlowStep {
        if let draft = recoveredDraft {
            return .review(draft)
        }
        return bypassingReadiness ? .camera : .readiness
    }
}
