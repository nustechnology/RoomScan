//
//  RoomModelCanvasCoordinator.swift
//  roomscan
//

import RealityKit
import simd
import SwiftUI
import UIKit

@MainActor
final class RoomModelCanvasCoordinator: NSObject, UIGestureRecognizerDelegate {
    struct ActivePinDrag {
        let planeNormal: SIMD3<Float>
    }

    struct PinAppearanceState: Equatable {
        let color: NoteColor
        let isSelected: Bool
    }

    var onPinTapped: (String) -> Void
    var onSurfaceTapped: (SIMD3<Float>) -> Void
    var onMoveDraftChanged: (SIMD3<Float>) -> Void
    var onCameraCommandConsumed: () -> Void
    var onModelLoaded: () -> Void
    var onModelLoadFailed: () -> Void
    var isPlacementMode = false
    var movingNoteID: String?
    var movePreviewPosition: SIMD3<Float>?

    weak var arView: ARView?
    var anchor: AnchorEntity?
    var camera: PerspectiveCamera?
    var roomEntity: Entity?
    var pinsRoot = Entity()
    var loadedSource: ModelSource?
    var currentViewMode: ViewerMode = .threeD
    var pendingFileSource: ModelSource?
    var lastAppliedCameraCommand: CameraCommand?

    private var yaw: Float = 0.55
    private var pitch: Float = 0.38
    private var distance: Float = 6.5
    private var target = SIMD3<Float>(0, 1.0, 0)
    private let defaultYaw: Float = 0.55
    private let defaultPitch: Float = 0.38
    private let defaultDistance: Float = 6.5
    private let defaultTarget = SIMD3<Float>(0, 1.0, 0)
    private let minDistance: Float = 2.5
    private let maxDistance: Float = 14
    /// Positive pitch = camera above target (looking down). Near π/2 = top view.
    private let minPitch: Float = 0.08
    private let maxPitch: Float = (.pi / 2) - 0.06

    private var lastOrbitPoint: CGPoint?
    private var lastPanPoint: CGPoint?
    private var activePinDrag: ActivePinDrag?
    var pinAppearanceStates: [ObjectIdentifier: PinAppearanceState] = [:]
    private var pinFacingTask: Task<Void, Never>?
    private let cameraAnimationDuration: TimeInterval = 0.35
    static var materialCache: [NoteColor: UnlitMaterial] = [:]

    init(
        onPinTapped: @escaping (String) -> Void,
        onSurfaceTapped: @escaping (SIMD3<Float>) -> Void,
        onMoveDraftChanged: @escaping (SIMD3<Float>) -> Void,
        onCameraCommandConsumed: @escaping () -> Void,
        onModelLoaded: @escaping () -> Void,
        onModelLoadFailed: @escaping () -> Void
    ) {
        self.onPinTapped = onPinTapped
        self.onSurfaceTapped = onSurfaceTapped
        self.onMoveDraftChanged = onMoveDraftChanged
        self.onCameraCommandConsumed = onCameraCommandConsumed
        self.onModelLoaded = onModelLoaded
        self.onModelLoadFailed = onModelLoadFailed
    }

    /// Loads the room entity for `source`. Returns `false` when a file source cannot be loaded.
    @discardableResult
    func loadModel(source: ModelSource) -> Bool {
        guard let anchor else { return false }
        roomEntity?.removeFromParent()
        pinsRoot.removeFromParent()
        loadedSource = nil
        pendingFileSource = nil

        switch source {
        case .sampleRoom:
            let room = SampleRoomFactory.makeRoom()
            RoomModelCollision.applyFilter(
                to: room,
                group: RoomModelCollision.roomSurfaceGroup,
                mask: RoomModelCollision.pinGroup
            )
            roomEntity = room
            loadedSource = source
            anchor.addChild(room)
            pinsRoot.name = "PinsRoot"
            anchor.addChild(pinsRoot)
            updateCamera(animated: false)
            DispatchQueue.main.async(execute: onModelLoaded)
            return true
        case .file(let url):
            pendingFileSource = source
            let notifyFailure = onModelLoadFailed
            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let room = try Entity.load(contentsOf: url)
                    room.generateCollisionShapes(recursive: true)
                    RoomModelCollision.applyFilter(
                        to: room,
                        group: RoomModelCollision.roomSurfaceGroup,
                        mask: RoomModelCollision.pinGroup
                    )
                    await MainActor.run {
                        guard let self,
                              self.pendingFileSource == source,
                              let anchor = self.anchor else { return }
                        self.pendingFileSource = nil
                        self.roomEntity?.removeFromParent()
                        self.roomEntity = room
                        self.loadedSource = source
                        anchor.addChild(room)
                        self.pinsRoot.name = "PinsRoot"
                        anchor.addChild(self.pinsRoot)
                        self.updateCamera(animated: false)
                        DispatchQueue.main.async(execute: self.onModelLoaded)
                    }
                } catch {
                    await MainActor.run {
                        guard let self, self.pendingFileSource == source else { return }
                        self.pendingFileSource = nil
                        self.loadedSource = nil
                        self.roomEntity = nil
                        DispatchQueue.main.async(execute: notifyFailure)
                    }
                }
            }
            return true
        }
    }

    func syncNotes(_ notes: [SpatialNote], selectedNoteID: String?) {
        let nextIDs = Set(notes.map(\.id))

        for child in Array(pinsRoot.children) where !nextIDs.contains(child.name) {
            pinAppearanceStates.removeValue(forKey: ObjectIdentifier(child))
            child.removeFromParent()
        }

        for note in notes {
            if let entity = pinsRoot.children.first(where: { $0.name == note.id }) {
                entity.position = note.position
                applyPinAppearance(to: entity, color: note.color, isSelected: note.id == selectedNoteID)
            } else {
                let pin = makePin(for: note, isSelected: note.id == selectedNoteID)
                pinsRoot.addChild(pin)
            }
        }

        updateAllPinModePresentations()

        if let camera {
            facePinsTowardCamera(eye: camera.position(relativeTo: nil))
        }
    }

    func applyViewMode(_ mode: ViewerMode, animated: Bool) {
        currentViewMode = mode
        switch mode {
        case .threeD:
            pitch = defaultPitch
            yaw = defaultYaw
            distance = defaultDistance
        case .topView:
            pitch = maxPitch
            yaw = 0
            distance = 8.5
        }
        target = defaultTarget
        updateAllPinModePresentations()
        updateCamera(animated: animated)
    }

    func applyCameraCommand(_ command: CameraCommand) {
        switch command {
        case .zoomIn:
            distance = max(minDistance, distance * 0.82)
        case .zoomOut:
            distance = min(maxDistance, distance * 1.22)
        case .reset:
            applyViewMode(currentViewMode, animated: true)
            return
        case .focus(let position):
            target = position
            distance = max(minDistance, min(distance, 5.5))
        }
        updateCamera(animated: true)
    }

    private func updateCamera(animated: Bool) {
        guard let camera else { return }
        let offset = SIMD3<Float>(
            distance * cos(pitch) * sin(yaw),
            distance * sin(pitch),
            distance * cos(pitch) * cos(yaw)
        )
        let eye = target + offset

        pinFacingTask?.cancel()
        pinFacingTask = nil
        camera.stopAllAnimations()

        guard animated else {
            camera.look(at: target, from: eye, relativeTo: nil)
            facePinsTowardCamera(eye: eye)
            return
        }

        let startTransform = camera.transform
        camera.look(at: target, from: eye, relativeTo: nil)
        let endTransform = camera.transform
        camera.transform = startTransform

        camera.move(
            to: endTransform,
            relativeTo: camera.parent,
            duration: cameraAnimationDuration,
            timingFunction: .easeInOut
        )

        let destinationEye = eye
        let duration = cameraAnimationDuration
        pinFacingTask = Task { @MainActor [weak self] in
            let deadline = Date().addingTimeInterval(duration)
            while !Task.isCancelled, Date() < deadline {
                guard let self, let camera = self.camera else { return }
                self.facePinsTowardCamera(eye: camera.position(relativeTo: nil))
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            guard !Task.isCancelled, let self else { return }
            self.facePinsTowardCamera(eye: destinationEye)
        }
    }

    private var cameraRight: SIMD3<Float> {
        let offset = SIMD3<Float>(
            distance * cos(pitch) * sin(yaw),
            distance * sin(pitch),
            distance * cos(pitch) * cos(yaw)
        )
        let forward = normalize(-offset)
        return normalize(cross(SIMD3<Float>(0, 1, 0), -forward))
    }

}

@MainActor
extension RoomModelCanvasCoordinator {
    func installGestures(on arView: ARView) {
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1
        orbit.delegate = self
        arView.addGestureRecognizer(orbit)

        let moveDrag = UILongPressGestureRecognizer(target: self, action: #selector(handleMoveDrag(_:)))
        moveDrag.minimumPressDuration = 0.15
        moveDrag.delegate = self
        arView.addGestureRecognizer(moveDrag)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        arView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        arView.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        arView.addGestureRecognizer(tap)
    }

    @objc private func handleOrbit(_ gesture: UIPanGestureRecognizer) {
        if activePinDrag != nil { return }
        guard currentViewMode == .threeD else { return }
        let point = gesture.location(in: gesture.view)
        switch gesture.state {
        case .began:
            lastOrbitPoint = point
        case .changed:
            guard let lastOrbitPoint else { return }
            let dx = Float(point.x - lastOrbitPoint.x)
            let dy = Float(point.y - lastOrbitPoint.y)
            yaw += dx * 0.01
            // Drag up → lower camera elevation; drag down → raise toward top view.
            pitch = min(maxPitch, max(minPitch, pitch + dy * 0.01))
            self.lastOrbitPoint = point
            updateCamera(animated: false)
        default:
            lastOrbitPoint = nil
        }
    }

    @objc private func handleMoveDrag(_ gesture: UILongPressGestureRecognizer) {
        guard let movingNoteID,
              let arView,
              let currentPosition = movePreviewPosition else {
            activePinDrag = nil
            return
        }

        let location = gesture.location(in: arView)
        switch gesture.state {
        case .began:
            let hits = arView.hitTest(location)
            guard let pinEntity = hits.lazy.compactMap({ self.findPinEntity(from: $0.entity) }).first,
                  pinEntity.name == movingNoteID,
                  let camera else {
                activePinDrag = nil
                return
            }
            activePinDrag = ActivePinDrag(
                planeNormal: normalize(currentPosition - camera.position(relativeTo: nil))
            )

        case .changed:
            guard let activePinDrag,
                  let updatedPosition = movedPosition(
                    from: currentPosition,
                    planeNormal: activePinDrag.planeNormal,
                    screenLocation: location,
                    in: arView
                  ) else { return }
            onMoveDraftChanged(updatedPosition)

        case .ended:
            activePinDrag = nil

        case .cancelled, .failed:
            activePinDrag = nil

        default:
            break
        }
    }

    private func movedPosition(
        from position: SIMD3<Float>,
        planeNormal: SIMD3<Float>,
        screenLocation: CGPoint,
        in arView: ARView
    ) -> SIMD3<Float>? {
        if let surfacePosition = firstSurfaceHitPosition(at: screenLocation, in: arView) {
            return surfacePosition
        }

        guard let ray = arView.ray(through: screenLocation) else { return nil }
        let direction = normalize(ray.direction)
        let denominator = simd_dot(direction, planeNormal)
        guard abs(denominator) > 0.0001 else { return nil }

        let distanceAlongRay = simd_dot(position - ray.origin, planeNormal) / denominator
        guard distanceAlongRay.isFinite else { return nil }
        return ray.origin + (direction * distanceAlongRay)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if activePinDrag != nil {
            return
        }
        let point = gesture.location(in: gesture.view)
        switch gesture.state {
        case .began:
            lastPanPoint = point
        case .changed:
            guard let lastPanPoint else { return }
            let dx = Float(point.x - lastPanPoint.x)
            let dy = Float(point.y - lastPanPoint.y)
            let right = cameraRight
            let forward = normalize(SIMD3<Float>(right.z, 0, -right.x))
            let scale = distance * 0.0018
            target += right * (-dx * scale) + forward * (dy * scale)
            self.lastPanPoint = point
            updateCamera(animated: false)
        default:
            lastPanPoint = nil
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            let factor = Float(gesture.scale)
            distance = max(minDistance, min(maxDistance, distance / factor))
            gesture.scale = 1
            updateCamera(animated: false)
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView, gesture.state == .ended else { return }
        let location = gesture.location(in: arView)
        let hits = arView.hitTest(location)

        if !isPlacementMode, let pinEntity = hits.lazy.compactMap({ self.findPinEntity(from: $0.entity) }).first {
            onPinTapped(pinEntity.name)
            return
        }

        guard isPlacementMode else { return }

        if let surfacePosition = firstSurfaceHitPosition(at: location, in: arView) {
            onSurfaceTapped(surfacePosition)
            return
        }

        if let floatingPosition = makeFloatingPlacementPosition(for: location, in: arView) {
            onSurfaceTapped(floatingPosition)
        }
    }

    private func makeFloatingPlacementPosition(for location: CGPoint, in arView: ARView) -> SIMD3<Float>? {
        guard let ray = arView.ray(through: location) else {
            return nil
        }

        let placementDistance = simd_distance(ray.origin, target)
        let clampedDistance = min(max(placementDistance, 0.75), 12)
        return ray.origin + (normalize(ray.direction) * clampedDistance)
    }

    private func findPinEntity(from entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.parent === pinsRoot, !candidate.name.isEmpty {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }

    private func firstSurfaceHitPosition(at location: CGPoint, in arView: ARView) -> SIMD3<Float>? {
        guard let ray = arView.ray(through: location) else { return nil }

        return arView.scene.raycast(
            origin: ray.origin,
            direction: normalize(ray.direction),
            length: maxDistance * 2,
            query: .nearest,
            mask: RoomModelCollision.roomSurfaceGroup,
            relativeTo: nil
        )
        .first(where: { isRoomSurfaceEntity($0.entity) })?
        .position
    }

    private func isRoomSurfaceEntity(_ entity: Entity) -> Bool {
        guard let roomEntity else { return false }

        var current: Entity? = entity
        while let candidate = current {
            if candidate === pinsRoot {
                return false
            }
            if candidate === roomEntity {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
