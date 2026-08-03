//
//  ModelPreviewCamera.swift
//  roomscan
//

import Foundation
import simd

/// Camera pose for the 3D model preview, expressed as an orbit around a pivot point.
///
/// A pose is always derived from the live scene camera immediately before a command is
/// applied and discarded afterwards. Nothing is stored between interactions, so SceneKit's
/// built-in gestures and the preview's own controls cannot drift apart.
nonisolated struct ModelPreviewCameraPose: Equatable {
    /// Distance kept between camera and pivot so the orbit never degenerates into a point.
    private static let minimumDistance: Float = 0.001

    /// Rotation around the pivot's vertical axis, in radians.
    let yaw: Float
    /// Elevation above the pivot, in radians. Positive values look down at the model.
    let pitch: Float
    /// Distance between the camera and the pivot.
    let distance: Float

    init(yaw: Float, pitch: Float, distance: Float) {
        self.yaw = yaw
        self.pitch = pitch
        self.distance = Swift.max(distance, Self.minimumDistance)
    }

    /// Derives the pose from a camera position so a manually dragged camera becomes the
    /// starting point of the next command.
    init(eye: SIMD3<Float>, pivot: SIMD3<Float>) {
        let offset = eye - pivot
        let distance = Swift.max(simd_length(offset), Self.minimumDistance)
        self.init(
            yaw: atan2(offset.x, offset.z),
            pitch: asin(Swift.min(Swift.max(offset.y / distance, -1), 1)),
            distance: distance
        )
    }

    /// Camera position this pose describes.
    func eye(around pivot: SIMD3<Float>) -> SIMD3<Float> {
        pivot + SIMD3<Float>(
            distance * cos(pitch) * sin(yaw),
            distance * sin(pitch),
            distance * cos(pitch) * cos(yaw)
        )
    }

    /// Turns around the pivot, keeping the current elevation and distance.
    func rotated(by radians: Float) -> ModelPreviewCameraPose {
        ModelPreviewCameraPose(yaw: yaw + radians, pitch: pitch, distance: distance)
    }

    /// Moves toward or away from the pivot, keeping the current orientation.
    func zoomed(by factor: Float, limits: ClosedRange<Float>) -> ModelPreviewCameraPose {
        ModelPreviewCameraPose(
            yaw: yaw,
            pitch: pitch,
            distance: Swift.min(Swift.max(distance * factor, limits.lowerBound), limits.upperBound)
        )
    }
}

/// Framing metrics derived from a model's bounds, used to place and clamp the preview camera.
nonisolated struct ModelPreviewFraming: Equatable {
    private static let fitMultiplier: Float = 1.8
    private static let minimumFitDistance: Float = 2.5
    /// Height of the initial camera above the pivot, as a fraction of the fitted distance.
    private static let initialElevationRatio: Float = 0.45
    private static let closestZoomRatio: Float = 0.3
    private static let farthestZoomRatio: Float = 2

    /// Center of the model, used as the default orbit pivot.
    let pivot: SIMD3<Float>
    /// Largest dimension of the model.
    let extent: Float

    init(pivot: SIMD3<Float>, extent: Float) {
        self.pivot = pivot
        self.extent = Swift.max(extent, 0)
    }

    /// Pose that frames the whole model when the preview first appears.
    var initialPose: ModelPreviewCameraPose {
        ModelPreviewCameraPose(
            yaw: 0,
            pitch: atan(Self.initialElevationRatio),
            distance: initialDistance
        )
    }

    /// Range the zoom controls may move the camera within.
    var distanceLimits: ClosedRange<Float> {
        (initialDistance * Self.closestZoomRatio)...(initialDistance * Self.farthestZoomRatio)
    }

    private var initialDistance: Float {
        let fitDistance = Swift.max(extent * Self.fitMultiplier, Self.minimumFitDistance)
        let elevation = Self.initialElevationRatio
        return fitDistance * (1 + elevation * elevation).squareRoot()
    }
}
