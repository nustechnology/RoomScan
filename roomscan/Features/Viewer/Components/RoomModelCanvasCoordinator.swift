//
//  RoomModelCanvasCoordinator.swift
//  roomscan
//

// swiftlint:disable file_length
// Combine→async load bridge types are kept in this file so they stay in
// compilation scope with the coordinator (separate files were not visible to
// some Xcode builds).

import Combine
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

    /// Canonical 3D-orbit resting pose. Logical fields, `displayedPose`, and reset
    /// all read from here so the literals exist once.
    private enum DefaultOrbit {
        static let yaw: Float = 0.55
        static let pitch: Float = 0.38
        static let distance: Float = 6.5
        static let target = SIMD3<Float>(0, 1.0, 0)

        static var pose: CameraOrbitPose {
            CameraOrbitPose(yaw: yaw, pitch: pitch, distance: distance, target: target)
        }
    }

    var onPinTapped: (String) -> Void
    var onSurfaceTapped: (SIMD3<Float>) -> Void
    var onMoveDraftChanged: (SIMD3<Float>) -> Void
    var onModelLoaded: @MainActor @Sendable () -> Void
    var onModelLoadFailed: @MainActor @Sendable () -> Void
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
    var appliedCameraCommandIDs: Set<UUID> = []

    private var yaw: Float = DefaultOrbit.yaw
    private var pitch: Float = DefaultOrbit.pitch
    private var distance: Float = DefaultOrbit.distance
    private var target = DefaultOrbit.target
    private let minDistance: Float = 2.5
    private let maxDistance: Float = 14
    /// Positive pitch = camera above target (looking down). Near π/2 = top view.
    private let minPitch: Float = 0.08
    private let maxPitch: Float = (.pi / 2) - 0.06

    /// Pose currently drawn on screen. Differs from logical `yaw`/`pitch`/`distance`/
    /// `target` while an orbit animation is in flight; interrupt starts from here.
    /// Seeded eagerly (not lazy from `logicalPose`) so the first animated
    /// `updateCamera` does not read start after the end pose was already written.
    private var displayedPose = DefaultOrbit.pose
    private var lastOrbitPoint: CGPoint?
    private var lastPanPoint: CGPoint?
    private var activePinDrag: ActivePinDrag?
    var pinAppearanceStates: [ObjectIdentifier: PinAppearanceState] = [:]
    private var cameraMotionDisplayLink: CADisplayLink?
    private var cameraMotionTickProxy: CameraMotionDisplayLinkProxy?
    private var cameraMotionStartPose = CameraOrbitPose(yaw: 0, pitch: 0, distance: 1, target: .zero)
    private var cameraMotionEndPose = CameraOrbitPose(yaw: 0, pitch: 0, distance: 1, target: .zero)
    private var cameraMotionDuration: TimeInterval = 0
    private var cameraMotionTiming: CameraMotionTiming = .easeInOut
    private var cameraMotionStartedAt: CFTimeInterval = 0
    private var modelLoadCancellable: AnyCancellable?
    private var modelLoadTask: Task<Void, Never>?
    /// Bumped on each `loadModel` / `cancelModelLoad` so deferred load reports cannot
    /// apply to a superseded or torn-down generation.
    private var modelLoadGeneration: UInt = 0
    private let cameraAnimationDuration: TimeInterval = 0.35
    /// Zoom buttons interrupt in-flight motion; easeOut starts moving immediately,
    /// unlike easeInOut whose first frames have near-zero velocity.
    private let zoomAnimationDuration: TimeInterval = 0.16
    static var materialCache: [NoteColor: UnlitMaterial] = [:]

    init(
        onPinTapped: @escaping (String) -> Void,
        onSurfaceTapped: @escaping (SIMD3<Float>) -> Void,
        onMoveDraftChanged: @escaping (SIMD3<Float>) -> Void,
        onModelLoaded: @escaping @MainActor @Sendable () -> Void,
        onModelLoadFailed: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onPinTapped = onPinTapped
        self.onSurfaceTapped = onSurfaceTapped
        self.onMoveDraftChanged = onMoveDraftChanged
        self.onModelLoaded = onModelLoaded
        self.onModelLoadFailed = onModelLoadFailed
    }

    /// Loads the room entity for `source`. Returns `false` when a file source cannot be loaded.
    @discardableResult
    func loadModel(source: ModelSource) -> Bool {
        guard let anchor else { return false }
        modelLoadGeneration &+= 1
        let generation = modelLoadGeneration
        roomEntity?.removeFromParent()
        pinsRoot.removeFromParent()
        loadedSource = nil
        pendingFileSource = nil
        modelLoadTask?.cancel()
        modelLoadTask = nil
        modelLoadCancellable?.cancel()
        modelLoadCancellable = nil

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
            // Defer off the current SwiftUI update cycle without capturing non-Sendable state
            // into a `DispatchQueue` `@Sendable` closure.
            scheduleModelLoadReport(generation: generation, success: true)
            return true
        case .file(let url):
            pendingFileSource = source
            modelLoadTask?.cancel()
            modelLoadCancellable?.cancel()
            modelLoadCancellable = nil
            // RealityKit entity load APIs are `@MainActor`. `Task.detached` + sync
            // `Entity.load` is invalid (isolation) and blocks the main thread.
            // `await Entity(contentsOf:)` / `loadAsync` suspend so file I/O and USDZ
            // decode do not occupy the main run loop while in flight.
            modelLoadTask = Task { @MainActor [weak self] in
                await self?.finishFileLoad(source: source, url: url, generation: generation)
            }
            return true
        }
    }

    private func finishFileLoad(source: ModelSource, url: URL, generation: UInt) async {
        do {
            let room: Entity
            if #available(iOS 18.0, *) {
                room = try await Entity(contentsOf: url)
            } else {
                room = try await loadEntityAsync(from: url)
            }
            try Task.checkCancellation()
            // Load has resumed on MainActor. Yield lets already-queued MainActor work
            // (loading UI) commit before `generateCollisionShapes`; it does not move
            // or shorten that hitch — RealityKit keeps collision generation on-main.
            await Task.yield()
            try Task.checkCancellation()
            await applyLoadedFileEntity(room, source: source, generation: generation)
        } catch is CancellationError {
            // Superseded by a newer load or view teardown — do not surface as failure.
        } catch {
            handleFileLoadFailure(source: source, generation: generation)
        }
    }

    /// iOS 17-compatible non-blocking load via Combine `LoadRequest`.
    private func loadEntityAsync(from url: URL) async throws -> Entity {
        let bridge = LoadRequestCancellableBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Entity, Error>) in
                // Install resume BEFORE subscribing so a synchronous cached delivery
                // cannot observe `resume == nil` and leak the continuation.
                bridge.install(resume: OnceResume(continuation))
                modelLoadCancellable?.cancel()
                let cancellable = Entity.loadAsync(contentsOf: url)
                    .sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .finished:
                                // No-op if `receiveValue` already resumed; otherwise avoid a leak.
                                bridge.resume(throwing: LoadRequestBridgeError.completedWithoutValue)
                            case .failure(let error):
                                bridge.resume(throwing: error)
                            }
                        },
                        receiveValue: { entity in
                            bridge.resume(returning: entity)
                        }
                    )
                bridge.attach(cancellable: cancellable)
                // MainActor-only bookkeeping for superseding loads; Combine callbacks
                // must not write this property (may run off the main queue).
                modelLoadCancellable = cancellable
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    private func applyLoadedFileEntity(_ room: Entity, source: ModelSource, generation: UInt) async {
        guard pendingFileSource == source,
              modelLoadGeneration == generation,
              let anchor else { return }

        // MainActor-only (RealityKit); cost scales with mesh complexity on every open.
        // Follow-ups: ShapeResource.generateStaticMesh off-actor, or bake at export.
        room.generateCollisionShapes(recursive: true)
        RoomModelCollision.applyFilter(
            to: room,
            group: RoomModelCollision.roomSurfaceGroup,
            mask: RoomModelCollision.pinGroup
        )
        await Task.yield()

        // Recheck after the yield: a newer load (including A→B→A) may have bumped generation
        // while collision generation ran past the last Task.checkCancellation().
        guard pendingFileSource == source, modelLoadGeneration == generation else { return }
        pendingFileSource = nil
        roomEntity?.removeFromParent()
        roomEntity = room
        loadedSource = source
        anchor.addChild(room)
        pinsRoot.name = "PinsRoot"
        anchor.addChild(pinsRoot)
        updateCamera(animated: false)
        scheduleModelLoadReport(generation: generation, success: true)
    }

    private func handleFileLoadFailure(source: ModelSource, generation: UInt) {
        guard pendingFileSource == source, modelLoadGeneration == generation else { return }
        pendingFileSource = nil
        loadedSource = nil
        roomEntity = nil
        scheduleModelLoadReport(generation: generation, success: false)
    }

    /// Schedules a load success/failure callback on the next MainActor turn.
    /// The report is dropped if `generation` no longer matches (superseded load or teardown).
    private func scheduleModelLoadReport(generation: UInt, success: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.modelLoadGeneration == generation else { return }
            if success {
                self.onModelLoaded()
            } else {
                self.onModelLoadFailed()
            }
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
        applyViewModePose(for: mode)
        updateAllPinModePresentations()
        updateCamera(animated: animated)
    }

}

@MainActor
extension RoomModelCanvasCoordinator {
    /// Cancels in-flight orbit animation. Call on view teardown so the display
    /// link does not outlive the `ARView`.
    func cancelCameraMotion() {
        cameraMotionDisplayLink?.invalidate()
        cameraMotionDisplayLink = nil
        cameraMotionTickProxy = nil
    }

    /// Cancels an in-flight model load. Call on view teardown so a late completion cannot
    /// keep generating collision shapes or attaching children to a detached `ARView`.
    func cancelModelLoad() {
        modelLoadGeneration &+= 1
        pendingFileSource = nil
        modelLoadTask?.cancel()
        modelLoadTask = nil
        modelLoadCancellable?.cancel()
        modelLoadCancellable = nil
    }

    fileprivate func applyViewModePose(for mode: ViewerMode) {
        switch mode {
        case .threeD:
            pitch = DefaultOrbit.pitch
            yaw = DefaultOrbit.yaw
            distance = DefaultOrbit.distance
        case .topView:
            pitch = maxPitch
            yaw = 0
            distance = 8.5
        }
        target = DefaultOrbit.target
    }

    fileprivate var logicalPose: CameraOrbitPose {
        CameraOrbitPose(yaw: yaw, pitch: pitch, distance: distance, target: target)
    }

    fileprivate func updateCamera(
        animated: Bool,
        duration: TimeInterval? = nil,
        timing: CameraMotionTiming = .easeInOut
    ) {
        guard let camera else { return }
        let end = logicalPose

        cancelCameraMotion()

        guard animated else {
            applyPose(end, to: camera)
            displayedPose = end
            facePinsTowardCameraIfNeeded(eye: end.eye)
            return
        }

        cameraMotionStartPose = displayedPose
        cameraMotionEndPose = end
        cameraMotionDuration = duration ?? cameraAnimationDuration
        cameraMotionTiming = timing
        cameraMotionStartedAt = CACurrentMediaTime()

        let proxy = CameraMotionDisplayLinkProxy(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(CameraMotionDisplayLinkProxy.handleTick(_:)))
        // Native display rate (60 or 120 on ProMotion). RealityKit previously drove
        // `camera.move` on the ARView's own link; pin facing is cheap / no-ops when empty.
        link.add(to: .main, forMode: .common)
        cameraMotionTickProxy = proxy
        cameraMotionDisplayLink = link
    }

    fileprivate func handleCameraMotionTick(_ link: CADisplayLink) {
        guard let camera else {
            cancelCameraMotion()
            return
        }

        let elapsed = CACurrentMediaTime() - cameraMotionStartedAt
        let linearT = min(1, Float(elapsed / cameraMotionDuration))
        if linearT >= 1 {
            // Land on the logical end so `displayedPose` matches `logicalPose` exactly for
            // the next interrupt (lerp's wrapped yaw can differ by a multiple of 2π).
            applyPose(cameraMotionEndPose, to: camera)
            displayedPose = cameraMotionEndPose
            facePinsTowardCameraIfNeeded(eye: cameraMotionEndPose.eye)
            cancelCameraMotion()
            return
        }

        let easedT = cameraMotionTiming.progress(linear: linearT)
        let pose = CameraOrbitPose.lerp(
            from: cameraMotionStartPose,
            to: cameraMotionEndPose,
            progress: easedT
        )
        applyPose(pose, to: camera)
        displayedPose = pose
        facePinsTowardCameraIfNeeded(eye: pose.eye)
    }

    private func facePinsTowardCameraIfNeeded(eye: SIMD3<Float>) {
        guard !pinsRoot.children.isEmpty else { return }
        facePinsTowardCamera(eye: eye)
    }

    private func applyPose(_ pose: CameraOrbitPose, to camera: PerspectiveCamera) {
        camera.look(at: pose.target, from: pose.eye, relativeTo: nil)
    }

    fileprivate var cameraRight: SIMD3<Float> {
        logicalPose.panRight
    }

}

// MARK: - Camera motion display-link proxy

/// Weak bridge so `CADisplayLink` does not retain the coordinator.
@MainActor
private final class CameraMotionDisplayLinkProxy: NSObject {
    weak var owner: RoomModelCanvasCoordinator?

    init(owner: RoomModelCanvasCoordinator) {
        self.owner = owner
        super.init()
    }

    @objc func handleTick(_ link: CADisplayLink) {
        guard let owner else {
            // Coordinator released without cancelCameraMotion — stop the run-loop retain.
            link.invalidate()
            return
        }
        owner.handleCameraMotionTick(link)
    }
}

@MainActor
extension RoomModelCanvasCoordinator {
    func applyCameraCommands(_ commands: [CameraCommand]) {
        guard !commands.isEmpty else { return }

        let isZoomOnly = commands.allSatisfy { command in
            switch command {
            case .zoomIn, .zoomOut: true
            case .reset, .focus: false
            }
        }
        // Only sync for zoom-only batches. Mixed batches may change `target` first
        // (e.g. focus then zoom); measuring against the pre-focus target is wrong.
        if isZoomOnly {
            syncOrbitDistanceFromDisplayedPose()
        }

        var shouldAnimate = true
        for command in commands {
            switch command {
            case .zoomIn:
                distance = max(minDistance, distance * 0.82)
            case .zoomOut:
                distance = min(maxDistance, distance * 1.22)
            case .reset:
                applyViewModePose(for: currentViewMode)
                updateAllPinModePresentations()
            case .focus(let position):
                target = position
                distance = max(minDistance, min(distance, 5.5))
                // Focus accompanies note selection, so it must not race the presenting sheet or gestures.
                shouldAnimate = false
            }
        }

        if isZoomOnly {
            updateCamera(
                animated: true,
                duration: zoomAnimationDuration,
                timing: .easeOut
            )
        } else {
            updateCamera(animated: shouldAnimate)
        }
    }

    /// Aligns logical orbit distance with the pose currently on screen.
    /// Used when zoom buttons interrupt an in-flight animation — yaw/pitch/target stay
    /// on the logical end pose so the short easeOut continues toward the destination mode.
    private func syncOrbitDistanceFromDisplayedPose() {
        distance = max(minDistance, min(maxDistance, displayedPose.distance))
    }

    /// Pinch zoom. While a mode/zoom animation is in flight, only distance is updated so
    /// orientation keeps lerping toward the logical end (no snap jump, no mid-pose freeze).
    fileprivate func adjustOrbitDistance(byFactor factor: Float) {
        let nextDistance = max(
            minDistance,
            min(maxDistance, displayedPose.distance / factor)
        )
        distance = nextDistance

        guard cameraMotionDisplayLink != nil else {
            updateCamera(animated: false)
            return
        }

        cameraMotionStartPose.distance = nextDistance
        cameraMotionEndPose.distance = nextDistance
        var pose = displayedPose
        pose.distance = nextDistance
        guard let camera else { return }
        applyPose(pose, to: camera)
        displayedPose = pose
        facePinsTowardCameraIfNeeded(eye: pose.eye)
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

    /// Copies the pose currently on screen into the logical fields.
    ///
    /// A gesture that interrupts an in-flight animation must continue from what the user
    /// sees, not snap to the animation's target (which `applyViewModePose` wrote into the
    /// logical fields before the animation started).
    private func syncLogicalPoseFromDisplayed() {
        yaw = displayedPose.yaw
        pitch = displayedPose.pitch
        distance = displayedPose.distance
        target = displayedPose.target
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
            syncLogicalPoseFromDisplayed()
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
            syncLogicalPoseFromDisplayed()
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
        guard gesture.state == .changed else { return }
        let factor = Float(gesture.scale)
        gesture.scale = 1
        adjustOrbitDistance(byFactor: factor)
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

// MARK: - Combine → async bridging (same file so types are always in module scope)

private enum LoadRequestBridgeError: Error {
    case completedWithoutValue
}

/// Holds the in-flight `LoadRequest` subscription so `onCancel` can stop it from any executor.
///
/// Ordering API: call `install(resume:)` before subscribing, then `attach(cancellable:)`.
/// That closes both races — cancel-before-install and resolve-before-attach (cached sync delivery).
nonisolated private final class LoadRequestCancellableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellable: AnyCancellable?
    private var resume: OnceResume<Entity>?
    private var isCancelled = false
    private var isResolved = false

    func install(resume: OnceResume<Entity>) {
        lock.lock()
        if isCancelled || isResolved {
            lock.unlock()
            resume.resume(throwing: isCancelled ? CancellationError() : LoadRequestBridgeError.completedWithoutValue)
            return
        }
        self.resume = resume
        lock.unlock()
    }

    func attach(cancellable: AnyCancellable) {
        lock.lock()
        if isCancelled || isResolved {
            lock.unlock()
            cancellable.cancel()
            return
        }
        self.cancellable = cancellable
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let toCancel = cancellable
        cancellable = nil
        let pending = resume
        resume = nil
        lock.unlock()
        // Cancel outside the lock — Combine completion may re-enter this box.
        toCancel?.cancel()
        pending?.resume(throwing: CancellationError())
    }

    func resume(returning value: Entity) {
        lock.lock()
        guard !isCancelled, !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let pending = resume
        resume = nil
        let toCancel = cancellable
        cancellable = nil
        lock.unlock()
        toCancel?.cancel()
        pending?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        guard !isCancelled, !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let pending = resume
        resume = nil
        let toCancel = cancellable
        cancellable = nil
        lock.unlock()
        toCancel?.cancel()
        pending?.resume(throwing: error)
    }
}

/// Ensures a checked continuation is resumed at most once.
nonisolated private final class OnceResume<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}
