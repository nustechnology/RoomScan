//
//  CameraOrbitPose.swift
//  roomscan
//

import Foundation
import simd

/// Shared by focus and gestures so a focused pose remains valid on the next drag/zoom.
nonisolated enum CameraOrbitLimits {
    static let minDistance: Float = 2.5
    static let maxDistance: Float = 14
    static let maxPitch: Float = (.pi / 2) - 0.06
    static let minPitch = -maxPitch
    /// Gesture orbit starts above the target plane unless focus already placed the
    /// camera below it with a clearance-checked pose.
    static let minGesturePitch: Float = 0.08

    static func clampedDistance(_ value: Float) -> Float {
        max(minDistance, min(maxDistance, value))
    }

    static func clampedPitch(_ value: Float) -> Float {
        max(minPitch, min(maxPitch, value))
    }

    static func gestureMinimumPitch(startingAt pitch: Float) -> Float {
        min(minGesturePitch, pitch)
    }

    static func clampedGesturePitch(_ value: Float, minimumPitch: Float) -> Float {
        max(minimumPitch, min(maxPitch, value))
    }
}

/// Orbit-camera state used by the room viewer. Keeping this free of RealityKit
/// lets unit tests cover lerp and interrupt policy without an `ARView`.
nonisolated struct CameraOrbitPose: Equatable, Sendable {
    var yaw: Float
    var pitch: Float
    var distance: Float
    var target: SIMD3<Float>

    var eye: SIMD3<Float> {
        target + offsetFromTarget
    }

    /// Vector from orbit `target` to `eye`.
    var offsetFromTarget: SIMD3<Float> {
        SIMD3<Float>(
            distance * cos(pitch) * sin(yaw),
            distance * sin(pitch),
            distance * cos(pitch) * cos(yaw)
        )
    }

    /// Direction from eye toward target.
    var forward: SIMD3<Float> {
        normalize(-offsetFromTarget)
    }

    /// Horizontal right for screen-space pan (world up crossed with look direction).
    var panRight: SIMD3<Float> {
        normalize(cross(SIMD3<Float>(0, 1, 0), -forward))
    }

    /// Linear interpolation. `progress` is expected in `[0, 1]` (caller applies easing).
    /// Yaw takes the shortest angular path so interrupts across the ±π wrap stay smooth.
    static func lerp(
        from start: CameraOrbitPose,
        to end: CameraOrbitPose,
        progress: Float
    ) -> CameraOrbitPose {
        let clamped = min(1, max(0, progress))
        return CameraOrbitPose(
            yaw: lerpYaw(start.yaw, end.yaw, progress: clamped),
            pitch: start.pitch + (end.pitch - start.pitch) * clamped,
            distance: start.distance + (end.distance - start.distance) * clamped,
            target: start.target + (end.target - start.target) * clamped
        )
    }

    /// Interpolates yaw along the shortest angular path, so any magnitude of accumulated
    /// yaw (it is never normalized) wraps into `[-π, π]` before scaling.
    private static func lerpYaw(_ start: Float, _ end: Float, progress: Float) -> Float {
        let delta = (end - start).remainder(dividingBy: Float.pi * 2)
        return start + delta * progress
    }
}

/// Timing curves for orbit-camera motion. Mirrors the RealityKit curves the
/// viewer used previously, without importing RealityKit into tests.
nonisolated enum CameraMotionTiming: Sendable {
    case easeInOut
    case easeOut

    /// Maps linear progress `fraction` in `[0, 1]` to eased progress in `[0, 1]`.
    func progress(linear fraction: Float) -> Float {
        let clamped = min(1, max(0, fraction))
        switch self {
        case .easeInOut:
            if clamped < 0.5 {
                return 2 * clamped * clamped
            }
            let inverted = -2 * clamped + 2
            return 1 - (inverted * inverted) / 2
        case .easeOut:
            let inverted = 1 - clamped
            return 1 - inverted * inverted
        }
    }
}
