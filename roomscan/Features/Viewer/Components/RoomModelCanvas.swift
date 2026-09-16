//
//  RoomModelCanvas.swift
//  roomscan
//

import RealityKit
import SwiftUI
import UIKit

struct RoomModelCanvas: UIViewRepresentable {
    typealias Coordinator = RoomModelCanvasCoordinator

    var modelSource: ModelSource
    var notes: [SpatialNote]
    var selectedNoteID: String?
    var viewMode: ViewerMode
    var isPlacementMode: Bool
    var movingNoteID: String?
    var movePreviewPosition: SIMD3<Float>?
    var cameraCommands: [PendingCameraCommand]
    var onCameraCommandsConsumed: (Set<UUID>) -> Void
    var onPinTapped: (String) -> Void
    var onSurfaceTapped: (SIMD3<Float>) -> Void
    var onMoveDraftChanged: (SIMD3<Float>) -> Void
    var onModelLoaded: @MainActor @Sendable () -> Void
    var onModelLoadFailed: @MainActor @Sendable () -> Void

    private func deferToNextViewUpdate(_ action: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    func makeCoordinator() -> RoomModelCanvasCoordinator {
        let notifyLoaded = onModelLoaded
        let notifyFailed = onModelLoadFailed
        return RoomModelCanvasCoordinator(
            onPinTapped: onPinTapped,
            onSurfaceTapped: onSurfaceTapped,
            onMoveDraftChanged: onMoveDraftChanged,
            onModelLoaded: { @MainActor @Sendable in notifyLoaded() },
            onModelLoadFailed: { @MainActor @Sendable in notifyFailed() }
        )
    }
}

extension RoomModelCanvas {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1))
        arView.renderOptions.insert(.disableMotionBlur)

        let contentAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(contentAnchor)
        context.coordinator.anchor = contentAnchor
        context.coordinator.arView = arView

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)
        context.coordinator.camera = camera

        context.coordinator.installGestures(on: arView)
        if !context.coordinator.loadModel(source: modelSource) {
            deferToNextViewUpdate(onModelLoadFailed)
        }
        context.coordinator.syncNotes(notes, selectedNoteID: selectedNoteID)
        context.coordinator.applyViewMode(viewMode, animated: false)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPinTapped = onPinTapped
        coordinator.onSurfaceTapped = onSurfaceTapped
        coordinator.onMoveDraftChanged = onMoveDraftChanged
        let notifyLoaded = onModelLoaded
        let notifyFailed = onModelLoadFailed
        coordinator.onModelLoaded = { @MainActor @Sendable in notifyLoaded() }
        coordinator.onModelLoadFailed = { @MainActor @Sendable in notifyFailed() }
        coordinator.isPlacementMode = isPlacementMode
        coordinator.movingNoteID = movingNoteID
        coordinator.movePreviewPosition = movePreviewPosition

        if coordinator.loadedSource != modelSource, coordinator.pendingFileSource != modelSource {
            if !coordinator.loadModel(source: modelSource) {
                deferToNextViewUpdate(onModelLoadFailed)
            }
        }

        coordinator.syncNotes(notes, selectedNoteID: selectedNoteID)

        if coordinator.currentViewMode != viewMode {
            coordinator.applyViewMode(viewMode, animated: true)
        }

        let commandIDs = Set(cameraCommands.map(\.id))
        let unapplied = cameraCommands.filter { !coordinator.appliedCameraCommandIDs.contains($0.id) }
        if !unapplied.isEmpty {
            coordinator.applyCameraCommands(unapplied.map(\.command))
            let ids = Set(unapplied.map(\.id))
            coordinator.appliedCameraCommandIDs.formUnion(ids)
            deferToNextViewUpdate { @MainActor @Sendable in
                onCameraCommandsConsumed(ids)
            }
        }

        coordinator.appliedCameraCommandIDs.formIntersection(commandIDs)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: RoomModelCanvasCoordinator) {
        coordinator.cancelCameraMotion()
        coordinator.cancelModelLoad()
        coordinator.anchor = nil
        coordinator.roomEntity = nil
        coordinator.arView = nil
        coordinator.camera = nil
    }
}
