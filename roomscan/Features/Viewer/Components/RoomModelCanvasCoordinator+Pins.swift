//
//  RoomModelCanvasCoordinator+Pins.swift
//  roomscan
//

import RealityKit
import simd
import SwiftUI
import UIKit

enum RoomModelCollision {
    static let roomSurfaceGroup = CollisionGroup(rawValue: 1 << 0)
    static let pinGroup = CollisionGroup(rawValue: 1 << 1)

    static func applyFilter(to entity: Entity, group: CollisionGroup, mask: CollisionGroup) {
        if var collision = entity.components[CollisionComponent.self] {
            collision.filter = CollisionFilter(group: group, mask: mask)
            entity.components.set(collision)
        }

        for child in entity.children {
            applyFilter(to: child, group: group, mask: mask)
        }
    }
}

@MainActor
extension RoomModelCanvasCoordinator {
    func makePin(for note: SpatialNote, isSelected: Bool) -> Entity {
        let root = Entity()
        root.name = note.id
        root.position = note.position
        let (billboard, topMarker) = makePinVisuals(color: note.color, isSelected: isSelected)
        root.addChild(billboard)
        root.addChild(topMarker)
        updatePinModePresentation(for: root)
        pinAppearanceStates[ObjectIdentifier(root)] = PinAppearanceState(
            color: note.color,
            isSelected: isSelected
        )
        return root
    }

    func applyPinAppearance(to entity: Entity, color: NoteColor, isSelected: Bool) {
        let appearanceState = PinAppearanceState(color: color, isSelected: isSelected)
        let entityID = ObjectIdentifier(entity)
        guard pinAppearanceStates[entityID] != appearanceState else { return }

        let size: Float = isSelected ? 0.28 : 0.22
        for child in entity.children {
            guard let model = child as? ModelEntity else { continue }
            switch child.name {
            case "pinBillboard":
                model.model?.mesh = .generatePlane(width: size, height: size)
                model.model?.materials = [Self.pinMaterial(color: color)]
                model.position = [0, size * 0.5, 0]
                model.generateCollisionShapes(recursive: false)
                RoomModelCollision.applyFilter(
                    to: model,
                    group: RoomModelCollision.pinGroup,
                    mask: RoomModelCollision.roomSurfaceGroup
                )
            case "pinTopMarker":
                let markerSize = topMarkerSize(for: isSelected)
                model.model?.mesh = .generatePlane(width: markerSize, height: markerSize)
                model.model?.materials = [Self.pinMaterial(color: color)]
                model.position = [0, 0.03, 0]
                model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                model.generateCollisionShapes(recursive: false)
                RoomModelCollision.applyFilter(
                    to: model,
                    group: RoomModelCollision.pinGroup,
                    mask: RoomModelCollision.roomSurfaceGroup
                )
            default:
                continue
            }
        }
        updatePinModePresentation(for: entity)
        pinAppearanceStates[entityID] = appearanceState
    }

    func facePinsTowardCamera(eye: SIMD3<Float>) {
        for pin in pinsRoot.children {
            let toCamera = normalize(eye - pin.position(relativeTo: nil))
            let yaw = atan2(toCamera.x, toCamera.z)
            pin.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
    }

    func makePinVisuals(color: NoteColor, isSelected: Bool) -> (ModelEntity, ModelEntity) {
        let size: Float = isSelected ? 0.28 : 0.22
        let billboard = ModelEntity(
            mesh: .generatePlane(width: size, height: size),
            materials: [Self.pinMaterial(color: color)]
        )
        billboard.name = "pinBillboard"
        billboard.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        billboard.position = [0, size * 0.5, 0]
        billboard.generateCollisionShapes(recursive: false)
        RoomModelCollision.applyFilter(
            to: billboard,
            group: RoomModelCollision.pinGroup,
            mask: RoomModelCollision.roomSurfaceGroup
        )

        let markerSize = topMarkerSize(for: isSelected)
        let topMarker = ModelEntity(
            mesh: .generatePlane(width: markerSize, height: markerSize),
            materials: [Self.pinMaterial(color: color)]
        )
        topMarker.name = "pinTopMarker"
        topMarker.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        topMarker.position = [0, 0.03, 0]
        topMarker.generateCollisionShapes(recursive: false)
        RoomModelCollision.applyFilter(
            to: topMarker,
            group: RoomModelCollision.pinGroup,
            mask: RoomModelCollision.roomSurfaceGroup
        )

        return (billboard, topMarker)
    }

    func updateAllPinModePresentations() {
        for pin in pinsRoot.children {
            updatePinModePresentation(for: pin)
        }
    }

    func updatePinModePresentation(for pin: Entity) {
        let showsTopMarker = currentViewMode == .topView
        for child in pin.children {
            switch child.name {
            case "pinBillboard":
                child.isEnabled = !showsTopMarker
            case "pinTopMarker":
                child.isEnabled = showsTopMarker
            default:
                continue
            }
        }
    }

    func topMarkerSize(for isSelected: Bool) -> Float {
        isSelected ? 0.4 : 0.32
    }

    static func pinMaterial(color: NoteColor) -> UnlitMaterial {
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

    static func pinUIImage(for color: NoteColor) -> UIImage {
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
}
