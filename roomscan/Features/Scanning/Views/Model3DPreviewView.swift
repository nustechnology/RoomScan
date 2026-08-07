//
//  Model3DPreviewView.swift
//  roomscan
//

import SceneKit
import SwiftUI

enum Model3DLoadState {
    case loading
    case loaded(SCNScene)
    case failed(SCNScene, message: String)
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
    @State private var cameraController = Model3DPreviewCameraController()

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

                case .failed(let fallbackScene, message: let message):
                    sceneView(for: fallbackScene)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.orange)
                                Text(message)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(20)
                            .background(Color.white.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(24)
                        }
                }
            }
            .aspectRatio(1.65, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(red: 0.87, green: 0.90, blue: 0.94), lineWidth: 1)
            }

            // Toolbar Controls (Rotate, Zoom in, Zoom out)
            HStack(spacing: 12) {
                controlButton(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: String(localized: "review.action.rotate"),
                    identifier: "review.rotateButton"
                ) {
                    cameraController.rotate()
                }

                controlButton(
                    systemImage: "plus",
                    title: String(localized: "review.action.zoom_in"),
                    identifier: "review.zoomInButton"
                ) {
                    cameraController.zoomIn()
                }

                controlButton(
                    systemImage: "minus",
                    title: String(localized: "review.action.zoom_out"),
                    identifier: "review.zoomOutButton"
                ) {
                    cameraController.zoomOut()
                }
            }
        }
        .task(id: meshURL) {
            await loadSceneStructured()
        }
        .onDisappear {
            // Release 3D scene memory immediately
            loadState = .loading
        }
    }

    private func sceneView(for scene: SCNScene) -> some View {
        Model3DSceneView(scene: scene, cameraController: cameraController)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func controlButton(
        systemImage: String,
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .accessibilityIdentifier(identifier)
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
            self.loadState = .loaded(wrapped.scene)
        } else {
            let fallback = Self.makeFallbackScene()
            self.loadState = .failed(
                fallback,
                message: String(localized: "review.model3d.load_failed")
            )
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
}

#Preview {
    Model3DPreviewView(meshURL: URL(fileURLWithPath: "/path/to/model.usdz"))
}
