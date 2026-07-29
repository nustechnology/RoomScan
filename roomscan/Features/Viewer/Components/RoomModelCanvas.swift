//
//  RoomModelCanvas.swift
//  roomscan
//

import RealityKit
import simd
import SwiftUI
import UIKit

struct RoomModelCanvas: UIViewRepresentable {
    var modelSource: ModelSource
    var notes: [SpatialNote]
    var selectedNoteID: String?
    var viewMode: ViewerMode
    var isPlacementMode: Bool
    var movingNoteID: String?
    var movePreviewPosition: SIMD3<Float>?
    var cameraCommand: CameraCommand?
    var onCameraCommandConsumed: () -> Void
    var onPinTapped: (String) -> Void
    var onSurfaceTapped: (SIMD3<Float>) -> Void
    var onMoveDraftChanged: (SIMD3<Float>) -> Void
    var onModelLoadFailed: () -> Void

    private func deferToNextViewUpdate(_ action: @escaping () -> Void) {
        DispatchQueue.main.async(execute: action)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPinTapped: onPinTapped,
            onSurfaceTapped: onSurfaceTapped,
            onMoveDraftChanged: onMoveDraftChanged,
            onCameraCommandConsumed: onCameraCommandConsumed,
            onModelLoadFailed: onModelLoadFailed
        )
    }

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
        coordinator.onCameraCommandConsumed = onCameraCommandConsumed
        coordinator.onModelLoadFailed = onModelLoadFailed
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

        if let cameraCommand {
            if coordinator.lastAppliedCameraCommand != cameraCommand {
                coordinator.applyCameraCommand(cameraCommand)
                coordinator.lastAppliedCameraCommand = cameraCommand
                deferToNextViewUpdate(onCameraCommandConsumed)
            }
        } else {
            coordinator.lastAppliedCameraCommand = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
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
        private var pinAppearanceStates: [ObjectIdentifier: PinAppearanceState] = [:]
        private static var materialCache: [NoteColor: UnlitMaterial] = [:]

        init(
            onPinTapped: @escaping (String) -> Void,
            onSurfaceTapped: @escaping (SIMD3<Float>) -> Void,
            onMoveDraftChanged: @escaping (SIMD3<Float>) -> Void,
            onCameraCommandConsumed: @escaping () -> Void,
            onModelLoadFailed: @escaping () -> Void
        ) {
            self.onPinTapped = onPinTapped
            self.onSurfaceTapped = onSurfaceTapped
            self.onMoveDraftChanged = onMoveDraftChanged
            self.onCameraCommandConsumed = onCameraCommandConsumed
            self.onModelLoadFailed = onModelLoadFailed
        }

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
                roomEntity = room
                loadedSource = source
                anchor.addChild(room)
                pinsRoot.name = "PinsRoot"
                anchor.addChild(pinsRoot)
                updateCamera(animated: false)
                return true
            case .file(let url):
                pendingFileSource = source
                let notifyFailure = onModelLoadFailed
                Task.detached(priority: .userInitiated) { [weak self] in
                    do {
                        let room = try Entity.load(contentsOf: url)
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
            _ = animated
            camera.look(at: target, from: eye, relativeTo: nil)
            facePinsTowardCamera(eye: eye)
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

        private func makePin(for note: SpatialNote, isSelected: Bool) -> Entity {
            let root = Entity()
            root.name = note.id
            root.position = note.position

            let size: Float = isSelected ? 0.28 : 0.22
            let plane = ModelEntity(
                mesh: .generatePlane(width: size, height: size),
                materials: [Self.pinMaterial(color: note.color)]
            )
            plane.name = "pinBillboard"
            // Stand upright in world space (plane is XY by default facing +Z).
            plane.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            plane.position = [0, size * 0.5, 0]
            plane.generateCollisionShapes(recursive: false)

            root.addChild(plane)
            pinAppearanceStates[ObjectIdentifier(root)] = PinAppearanceState(
                color: note.color,
                isSelected: isSelected
            )
            return root
        }

        private func applyPinAppearance(to entity: Entity, color: NoteColor, isSelected: Bool) {
            let appearanceState = PinAppearanceState(color: color, isSelected: isSelected)
            let entityID = ObjectIdentifier(entity)
            guard pinAppearanceStates[entityID] != appearanceState else { return }

            let size: Float = isSelected ? 0.28 : 0.22
            for child in entity.children {
                guard let model = child as? ModelEntity, child.name == "pinBillboard" else { continue }
                model.model?.mesh = .generatePlane(width: size, height: size)
                model.model?.materials = [Self.pinMaterial(color: color)]
                model.position = [0, size * 0.5, 0]
                model.generateCollisionShapes(recursive: false)
            }
            pinAppearanceStates[entityID] = appearanceState
        }

        private func facePinsTowardCamera(eye: SIMD3<Float>) {
            for pin in pinsRoot.children {
                let toCamera = normalize(eye - pin.position(relativeTo: nil))
                // Y-up billboard: yaw only so pin stays upright.
                let yaw = atan2(toCamera.x, toCamera.z)
                pin.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            }
        }

        private static func pinMaterial(color: NoteColor) -> UnlitMaterial {
            if let cached = materialCache[color] {
                return cached
            }
            let image = pinUIImage(for: color)
            if let cgImage = image.cgImage,
               let texture = try? TextureResource.generate(
                from: cgImage,
                options: TextureResource.CreateOptions(semantic: .color)
               ) {
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                material.blending = .transparent(opacity: .init(scale: 1))
                materialCache[color] = material
                return material
            }

            let fallback = UnlitMaterial(color: UIColor(color.swiftUIColor))
            materialCache[color] = fallback
            return fallback
        }

        private static func pinUIImage(for color: NoteColor) -> UIImage {
            let assetName = color.pinImageName
            let size = CGSize(width: 256, height: 256)
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size, format: format)

            return renderer.image { context in
                UIColor.clear.setFill()
                context.fill(CGRect(origin: .zero, size: size))

                if let image = UIImage(named: assetName) {
                    image.draw(in: CGRect(origin: .zero, size: size))
                } else {
                    let config = UIImage.SymbolConfiguration(pointSize: 96, weight: .bold)
                    let symbol = UIImage(systemName: "mappin.circle.fill", withConfiguration: config)?
                        .withTintColor(UIColor(color.swiftUIColor), renderingMode: .alwaysOriginal)
                    symbol?.draw(in: CGRect(origin: .zero, size: size))
                }
            }
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

            if let hit = hits.first {
                onSurfaceTapped(hit.position)
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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

enum SampleRoomFactory {
    static func makeRoom() -> Entity {
        let root = Entity()
        root.name = "SampleRoom"

        let floorMaterial = SimpleMaterial(
            color: UIColor(white: 0.88, alpha: 1),
            roughness: 0.85,
            isMetallic: false
        )
        let wallMaterial = SimpleMaterial(
            color: UIColor(red: 0.78, green: 0.84, blue: 0.90, alpha: 1),
            roughness: 0.9,
            isMetallic: false
        )
        let accentMaterial = SimpleMaterial(
            color: UIColor(red: 0.62, green: 0.72, blue: 0.82, alpha: 1),
            roughness: 0.8,
            isMetallic: false
        )

        let floor = ModelEntity(
            mesh: .generateBox(width: 4.2, height: 0.06, depth: 5.2),
            materials: [floorMaterial]
        )
        floor.position = [0, 0, 0]
        floor.generateCollisionShapes(recursive: false)
        root.addChild(floor)

        let backWall = ModelEntity(
            mesh: .generateBox(width: 4.2, height: 2.6, depth: 0.08),
            materials: [wallMaterial]
        )
        backWall.position = [0, 1.3, -2.55]
        backWall.generateCollisionShapes(recursive: false)
        root.addChild(backWall)

        let leftWall = ModelEntity(
            mesh: .generateBox(width: 0.08, height: 2.6, depth: 5.2),
            materials: [wallMaterial]
        )
        leftWall.position = [-2.1, 1.3, 0]
        leftWall.generateCollisionShapes(recursive: false)
        root.addChild(leftWall)

        let rightWall = ModelEntity(
            mesh: .generateBox(width: 0.08, height: 2.6, depth: 5.2),
            materials: [wallMaterial]
        )
        rightWall.position = [2.1, 1.3, 0]
        rightWall.generateCollisionShapes(recursive: false)
        root.addChild(rightWall)

        let sofa = ModelEntity(
            mesh: .generateBox(width: 1.8, height: 0.55, depth: 0.75),
            materials: [accentMaterial]
        )
        sofa.position = [0.2, 0.3, 1.4]
        sofa.generateCollisionShapes(recursive: false)
        root.addChild(sofa)

        let table = ModelEntity(
            mesh: .generateBox(width: 0.9, height: 0.4, depth: 0.55),
            materials: [floorMaterial]
        )
        table.position = [0.2, 0.22, 0.55]
        table.generateCollisionShapes(recursive: false)
        root.addChild(table)

        return root
    }
}
