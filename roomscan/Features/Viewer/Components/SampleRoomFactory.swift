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
