//
//  Model3DPreviewView.swift
//  roomscan
//

import SwiftUI
import SceneKit

enum Model3DLoadState {
    case loading
    case loaded(SCNScene)
    case failed(SCNScene)
}

/// Explicit `@unchecked Sendable` wrapper for passing `SCNScene` across isolation boundaries.
/// - Rationale: `SCNScene` is not natively marked `Sendable` in SceneKit framework headers,
///   but when constructed sequentially on a detached background worker thread and handed off
///   directly to `@MainActor` without concurrent modifications, transferring the scene reference
///   via this wrapper is thread-safe.
struct UncheckedSendableScene: @unchecked Sendable {
    let scene: SCNScene
}

private struct SCNSceneLoader {
    nonisolated static func loadScene(from meshURL: URL) -> UncheckedSendableScene? {
        guard FileManager.default.fileExists(atPath: meshURL.path) else { return nil }
        do {
            let loadedScene = try SCNScene(url: meshURL, options: nil)
            loadedScene.background.contents = UIColor(
                red: 239 / 255,
                green: 244 / 255,
                blue: 250 / 255,
                alpha: 1
            )
            let geometryCount = countGeometryNodes(in: loadedScene.rootNode)
            guard geometryCount > 0 else { return nil }
            return UncheckedSendableScene(scene: loadedScene)
        } catch {
            return nil
        }
    }

    private nonisolated static func countGeometryNodes(in node: SCNNode) -> Int {
        let ownGeometryCount = node.geometry == nil ? 0 : 1
        return ownGeometryCount + node.childNodes.reduce(0) {
            $0 + countGeometryNodes(in: $1)
        }
    }
}

struct Model3DPreviewView: View {
    let meshURL: URL

    @State private var loadState: Model3DLoadState = .loading
    @State private var cameraAngleY: Float = 0
    @State private var cameraZoom: Float = 5.0
    @State private var cameraNode: SCNNode?

    private var currentScene: SCNScene? {
        switch loadState {
        case .loaded(let scene), .failed(let scene):
            return scene
        case .loading:
            return nil
        }
    }

    private let previewBackground = Color(
        red: 239 / 255,
        green: 244 / 255,
        blue: 250 / 255
    )

    init(meshURL: URL) {
        self.meshURL = meshURL
    }

    var body: some View {
        VStack(spacing: 20) {
            // Interactive Scene Container
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(previewBackground)

                switch loadState {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "review.model3d.loading"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .loaded(let scene):
                    sceneView(for: scene)

                case .failed(let fallbackScene):
                    sceneView(for: fallbackScene)
                }
            }
            .aspectRatio(1.65, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(red: 0.87, green: 0.90, blue: 0.94), lineWidth: 1)
            }

            // Toolbar Controls (Rotate, Zoom in, Zoom out)
            HStack(spacing: 12) {
                Button {
                    cameraAngleY += 45
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(String(localized: "review.action.rotate"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                .accessibilityIdentifier("review.rotateButton")

                Button {
                    cameraZoom = max(1.5, cameraZoom - 0.8)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(String(localized: "review.action.zoom_in"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                .accessibilityIdentifier("review.zoomInButton")

                Button {
                    cameraZoom = min(10.0, cameraZoom + 0.8)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "minus")
                        Text(String(localized: "review.action.zoom_out"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                .accessibilityIdentifier("review.zoomOutButton")
            }
        }
        .task(id: meshURL) {
            await loadSceneStructured()
        }
        .onChange(of: cameraAngleY) { _, _ in
            if let cameraNode, let currentScene {
                updateCameraPosition(node: cameraNode, for: currentScene)
            }
        }
        .onChange(of: cameraZoom) { _, _ in
            if let cameraNode, let currentScene {
                updateCameraPosition(node: cameraNode, for: currentScene)
            }
        }
        .onDisappear {
            // Release 3D scene memory immediately
            loadState = .loading
            cameraNode = nil
        }
    }

    private func sceneView(for scene: SCNScene) -> some View {
        let node = cameraNode ?? createCameraNode(for: scene)
        return SceneView(
            scene: scene,
            pointOfView: node,
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func loadSceneStructured() async {
        let url = meshURL
        guard !Task.isCancelled else { return }

        // Perform heavy USDZ file loading & scene parsing on background worker thread off MainActor
        let wrapped = await Task.detached(priority: .userInitiated) { () -> UncheckedSendableScene? in
            SCNSceneLoader.loadScene(from: url)
        }.value

        guard !Task.isCancelled else { return }

        if let wrapped {
            self.cameraNode = self.createCameraNode(for: wrapped.scene)
            self.loadState = .loaded(wrapped.scene)
        } else {
            let fallback = Self.makeFallbackScene()
            self.cameraNode = self.createCameraNode(for: fallback)
            self.loadState = .failed(fallback)
        }
    }

    private static func makeFallbackScene() -> SCNScene {
        let scene = SCNScene()
        let box = SCNBox(width: 2.0, height: 1.2, length: 2.0, chamferRadius: 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemBlue
        material.fillMode = .lines
        box.materials = [material]

        let boxNode = SCNNode(geometry: box)
        boxNode.eulerAngles = SCNVector3(x: Float.pi / 6, y: Float.pi / 4, z: 0)
        scene.rootNode.addChildNode(boxNode)

        scene.background.contents = UIColor(
            red: 239 / 255,
            green: 244 / 255,
            blue: 250 / 255,
            alpha: 1
        )

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.8, alpha: 1.0)
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = UIColor(white: 1.0, alpha: 1.0)
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.position = SCNVector3(x: 5, y: 10, z: 8)
        directionalNode.eulerAngles = SCNVector3(x: -Float.pi / 4, y: Float.pi / 4, z: 0)
        scene.rootNode.addChildNode(directionalNode)

        return scene
    }

    private func createCameraNode(for scene: SCNScene) -> SCNNode {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        updateCameraPosition(node: cameraNode, for: scene)
        return cameraNode
    }

    private func updateCameraPosition(node: SCNNode, for scene: SCNScene) {
        let rad = Float(cameraAngleY) * Float.pi / 180.0
        let bounds = scene.rootNode.boundingBox
        let center = SCNVector3(
            x: (bounds.min.x + bounds.max.x) / 2,
            y: (bounds.min.y + bounds.max.y) / 2,
            z: (bounds.min.z + bounds.max.z) / 2
        )
        let extentX = bounds.max.x - bounds.min.x
        let extentY = bounds.max.y - bounds.min.y
        let extentZ = bounds.max.z - bounds.min.z
        let modelExtent = max(extentX, max(extentY, extentZ))
        let baseDistance = max(modelExtent * 1.8, 2.5)
        let distance = baseDistance * (cameraZoom / 5.0)

        let x = center.x + distance * sin(rad)
        let z = center.z + distance * cos(rad)
        let y = center.y + distance * 0.45

        node.position = SCNVector3(x: x, y: y, z: z)
        node.look(at: center)
        node.camera?.zNear = 0.01
        node.camera?.zFar = Double(max(distance * 20, 100))
    }
}
