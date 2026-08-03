//
//  Model3DSceneView.swift
//  roomscan
//

import SceneKit
import SwiftUI

/// Renders a loaded scene in an `SCNView` and lets `cameraController` drive the camera,
/// so `allowsCameraControl` gestures and the preview toolbar act on the same view.
struct Model3DSceneView: UIViewRepresentable {
    let scene: SCNScene
    let cameraController: Model3DPreviewCameraController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        cameraController.attach(scene: scene, to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        cameraController.attach(scene: scene, to: uiView)
    }
}

/// Moves the preview camera in response to the toolbar controls.
///
/// Every command reads the pose back from the live `pointOfView` and orbits SceneKit's own
/// camera target, so a command always continues from wherever the user's last gesture left
/// the camera, and gestures continue from wherever a command left it.
@MainActor
final class Model3DPreviewCameraController {
    private static let rotationStep = Float.pi / 4
    private static let zoomInFactor: Float = 0.84
    private static let animationDuration: TimeInterval = 0.3
    /// Multiple of the camera distance kept visible behind the model.
    private static let farClippingMultiplier: Float = 20
    private static let minimumFarClipping: Float = 100

    private let cameraNode: SCNNode = {
        let node = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.01
        node.camera = camera
        return node
    }()

    private weak var sceneView: SCNView?
    private weak var attachedScene: SCNScene?
    private var framing: ModelPreviewFraming?
    private var runningAnimations = 0

    func attach(scene: SCNScene, to view: SCNView) {
        guard attachedScene !== scene || sceneView !== view else { return }

        // Measure the model before the camera joins the graph, otherwise the camera's own
        // position would feed back into the bounding box used to place it.
        let framing = ModelPreviewFraming(rootNode: scene.rootNode)
        self.framing = framing

        cameraNode.removeFromParentNode()
        scene.rootNode.addChildNode(cameraNode)
        view.scene = scene
        view.pointOfView = cameraNode

        let controller = view.defaultCameraController
        controller.interactionMode = .orbitTurntable
        controller.automaticTarget = false
        controller.target = SCNVector3(framing.pivot)

        attachedScene = scene
        sceneView = view
        apply(framing.initialPose, pivot: framing.pivot, animated: false)
    }

    func rotate() {
        move { pose, _ in pose.rotated(by: Self.rotationStep) }
    }

    func zoomIn() {
        move { pose, framing in
            pose.zoomed(by: Self.zoomInFactor, limits: framing.distanceLimits)
        }
    }

    func zoomOut() {
        move { pose, framing in
            pose.zoomed(by: 1 / Self.zoomInFactor, limits: framing.distanceLimits)
        }
    }

    private func move(
        _ transform: (ModelPreviewCameraPose, ModelPreviewFraming) -> ModelPreviewCameraPose
    ) {
        guard let sceneView, let framing, let pointOfView = sceneView.pointOfView else { return }

        // SceneKit orbits and pans around its controller target, so that is the pivot the
        // user is actually looking at, not the pivot the model started at.
        let pivot = SIMD3<Float>(sceneView.defaultCameraController.target)
        let current = ModelPreviewCameraPose(eye: pointOfView.simdWorldPosition, pivot: pivot)
        apply(transform(current, framing), pivot: pivot, animated: true)
    }

    private func apply(_ pose: ModelPreviewCameraPose, pivot: SIMD3<Float>, animated: Bool) {
        guard let sceneView, let pointOfView = sceneView.pointOfView else { return }
        let eye = pose.eye(around: pivot)

        // Keep SceneKit's controller orbiting the same pivot once the camera has moved.
        sceneView.defaultCameraController.target = SCNVector3(pivot)

        let reposition = {
            pointOfView.simdWorldPosition = eye
            pointOfView.simdLook(at: pivot)
            pointOfView.camera?.zFar = Double(
                max(pose.distance * Self.farClippingMultiplier, Self.minimumFarClipping)
            )
        }

        guard animated else {
            reposition()
            return
        }

        beginAnimation(in: sceneView)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = Self.animationDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor in self?.endAnimation() }
        }
        reposition()
        SCNTransaction.commit()
    }

    /// `SCNView` only redraws on demand, so the render loop has to run while a camera
    /// animation is in flight.
    private func beginAnimation(in view: SCNView) {
        runningAnimations += 1
        view.rendersContinuously = true
    }

    private func endAnimation() {
        runningAnimations = max(0, runningAnimations - 1)
        guard runningAnimations == 0 else { return }
        sceneView?.rendersContinuously = false
    }
}

private extension ModelPreviewFraming {
    init(rootNode: SCNNode) {
        let bounds = rootNode.boundingBox
        let lower = SIMD3<Float>(bounds.min)
        let upper = SIMD3<Float>(bounds.max)
        self.init(pivot: (lower + upper) / 2, extent: (upper - lower).max())
    }
}
