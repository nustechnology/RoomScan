//
//  SampleRoomFactory.swift
//  roomscan
//

import RealityKit
import UIKit

enum SampleRoomFactory {
    static func makeRoom() -> Entity {
        let root = Entity()
        root.name = "SampleRoom"

        let materials = MaterialPalette()
        addRoomShell(to: root, materials: materials)
        addLivingZone(to: root, materials: materials)
        addDiningZone(to: root, materials: materials)
        addStorageZone(to: root, materials: materials)

        return root
    }
}

private extension SampleRoomFactory {
    struct MaterialPalette {
        let floor = SimpleMaterial(
            color: UIColor(white: 0.88, alpha: 1),
            roughness: 0.85,
            isMetallic: false
        )
        let wall = SimpleMaterial(
            color: UIColor(red: 0.78, green: 0.84, blue: 0.90, alpha: 1),
            roughness: 0.9,
            isMetallic: false
        )
        let accent = SimpleMaterial(
            color: UIColor(red: 0.62, green: 0.72, blue: 0.82, alpha: 1),
            roughness: 0.8,
            isMetallic: false
        )
        let wood = SimpleMaterial(
            color: UIColor(red: 0.67, green: 0.56, blue: 0.44, alpha: 1),
            roughness: 0.95,
            isMetallic: false
        )
        let dark = SimpleMaterial(
            color: UIColor(red: 0.28, green: 0.31, blue: 0.35, alpha: 1),
            roughness: 0.82,
            isMetallic: false
        )
        let lightAccent = SimpleMaterial(
            color: UIColor(red: 0.84, green: 0.78, blue: 0.70, alpha: 1),
            roughness: 0.88,
            isMetallic: false
        )
    }

    static func addRoomShell(to root: Entity, materials: MaterialPalette) {
        root.addConfiguredBox(
            width: 4.2,
            height: 0.06,
            depth: 5.2,
            materials: [materials.floor],
            position: [0, 0, 0]
        )
        root.addConfiguredBox(
            width: 4.2,
            height: 2.6,
            depth: 0.08,
            materials: [materials.wall],
            position: [0, 1.3, -2.55]
        )
        root.addConfiguredBox(
            width: 0.08,
            height: 2.6,
            depth: 5.2,
            materials: [materials.wall],
            position: [-2.1, 1.3, 0]
        )
        root.addConfiguredBox(
            width: 0.08,
            height: 2.6,
            depth: 5.2,
            materials: [materials.wall],
            position: [2.1, 1.3, 0]
        )
    }

    static func addLivingZone(to root: Entity, materials: MaterialPalette) {
        root.addConfiguredBox(
            width: 1.8,
            height: 0.55,
            depth: 0.75,
            materials: [materials.accent],
            position: [0.2, 0.3, 1.4]
        )
        root.addConfiguredBox(
            width: 0.9,
            height: 0.4,
            depth: 0.55,
            materials: [materials.floor],
            position: [0.2, 0.22, 0.55]
        )
        root.addConfiguredBox(
            width: 1.8,
            height: 0.02,
            depth: 1.25,
            materials: [materials.lightAccent],
            position: [0.2, 0.02, 0.72]
        )
        root.addConfiguredBox(
            width: 1.5,
            height: 0.55,
            depth: 0.42,
            materials: [materials.wood],
            position: [0, 0.28, -2.2]
        )
        root.addConfiguredBox(
            width: 1.05,
            height: 0.62,
            depth: 0.05,
            materials: [materials.dark],
            position: [0, 1.45, -2.47]
        )
        root.addConfiguredBox(
            width: 0.28,
            height: 0.05,
            depth: 0.28,
            materials: [materials.dark],
            position: [-1.72, 0.03, 1.2]
        )
        root.addConfiguredBox(
            width: 0.05,
            height: 1.5,
            depth: 0.05,
            materials: [materials.dark],
            position: [-1.72, 0.78, 1.2]
        )
        root.addConfiguredBox(
            width: 0.34,
            height: 0.26,
            depth: 0.34,
            materials: [materials.lightAccent],
            position: [-1.72, 1.58, 1.2]
        )
    }

    static func addDiningZone(to root: Entity, materials: MaterialPalette) {
        root.addConfiguredBox(
            width: 1.35,
            height: 0.08,
            depth: 0.8,
            materials: [materials.wood],
            position: [-1.15, 0.76, -0.15]
        )
        root.addConfiguredBox(
            width: 0.22,
            height: 0.72,
            depth: 0.22,
            materials: [materials.dark],
            position: [-1.15, 0.36, -0.15]
        )

        let chairPositions: [SIMD3<Float>] = [
            [-1.15, 0.24, -0.88],
            [-1.15, 0.24, 0.58],
            [-1.82, 0.24, -0.15],
            [-0.48, 0.24, -0.15]
        ]
        for position in chairPositions {
            root.addConfiguredBox(
                width: 0.42,
                height: 0.08,
                depth: 0.42,
                materials: [materials.accent],
                position: position
            )
            root.addConfiguredBox(
                width: 0.42,
                height: 0.45,
                depth: 0.06,
                materials: [materials.accent],
                position: [position.x, position.y + 0.24, position.z - 0.18]
            )
        }

        root.addConfiguredBox(
            width: 0.72,
            height: 0.92,
            depth: 1.85,
            materials: [materials.wood],
            position: [1.7, 0.46, -1.25]
        )
        root.addConfiguredBox(
            width: 0.58,
            height: 2.1,
            depth: 0.62,
            materials: [materials.dark],
            position: [1.7, 1.05, -2.12]
        )
    }

    static func addStorageZone(to root: Entity, materials: MaterialPalette) {
        root.addConfiguredBox(
            width: 0.95,
            height: 1.7,
            depth: 0.28,
            materials: [materials.wood],
            position: [-1.62, 0.85, 2.02]
        )
        root.addConfiguredBox(
            width: 1.1,
            height: 0.72,
            depth: 0.38,
            materials: [materials.wood],
            position: [1.05, 0.36, 2.0]
        )
        root.addConfiguredBox(
            width: 0.32,
            height: 0.42,
            depth: 0.32,
            materials: [materials.accent],
            position: [1.72, 0.21, 1.92]
        )
    }
}

private extension Entity {
    func addConfiguredBox(
        width: Float,
        height: Float,
        depth: Float,
        materials: [any Material],
        position: SIMD3<Float>
    ) {
        let box = ModelEntity(
            mesh: .generateBox(width: width, height: height, depth: depth),
            materials: materials
        )
        box.position = position
        box.generateCollisionShapes(recursive: false)
        addChild(box)
    }
}
