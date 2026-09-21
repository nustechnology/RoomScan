//
//  NoteFocusSolver.swift
//  roomscan
//

import Foundation
import simd

/// Pure helper for choosing the orbit direction used when focusing a note.
/// Kept free of RealityKit so unit tests can cover the angle math without an `ARView`.
nonisolated enum NoteFocusSolver {
    static let rayOriginOffset: Float = 0.05
    static let preferredDistance: Float = 3.2
    static let topViewDistanceCap: Float = 5.5
    static let occlusionTolerance: Float = 0.1

    /// A missing hit means open space. Hit distances must be measured from target,
    /// not from the offset ray origin. Never expand a short clearance to the orbit minimum.
    static func safeDistance(surfaceDistance: Float?) -> Float? {
        guard let surfaceDistance else { return preferredDistance }
        guard surfaceDistance.isFinite, surfaceDistance > 0 else { return nil }
        let safe = min(preferredDistance, surfaceDistance * 0.85)
        guard safe >= CameraOrbitLimits.minDistance else { return nil }
        return safe
    }

    static func hasClearLineOfSight(hitDistance: Float?, targetDistance: Float) -> Bool {
        guard targetDistance.isFinite, targetDistance > 0 else { return false }
        guard let hitDistance else { return true }
        return hitDistance.isFinite && hitDistance >= max(0, targetDistance - occlusionTolerance)
    }

    static func topViewPose(from pose: CameraOrbitPose, note: SIMD3<Float>) -> CameraOrbitPose {
        var result = pose
        result.target = note
        result.distance = CameraOrbitLimits.clampedDistance(min(pose.distance, topViewDistanceCap))
        return result
    }

    /// Geometry is supplied by the coordinator; tests can exercise the same selection
    /// policy without an ARView. An unsuccessful search never returns an unchecked pose.
    static func resolve(
        note: SIMD3<Float>,
        displayedPose: CameraOrbitPose,
        roomCenter: SIMD3<Float>?,
        surfaceDistance: (SIMD3<Float>, SIMD3<Float>) -> Float?,
        lineOfSight: (SIMD3<Float>, SIMD3<Float>) -> Bool
    ) -> CameraOrbitPose? {
        let target = note + SIMD3<Float>(0, 0.12, 0)
        let inward = roomCenter.flatMap { direction(from: note, to: $0) } ?? -displayedPose.forward
        let candidates = candidateDirections(
            inward: inward,
            current: direction(from: target, to: displayedPose.eye),
            elevation: 0.28
        )
        for candidate in candidates {
            let angles = orbitAngles(
                forDirection: candidate,
                minPitch: CameraOrbitLimits.minPitch,
                maxPitch: CameraOrbitLimits.maxPitch,
                fallbackYaw: displayedPose.yaw
            )
            let offset = offsetDirection(yaw: angles.yaw, pitch: angles.pitch)
            guard let distance = safeDistance(surfaceDistance: surfaceDistance(target, offset)) else { continue }
            let pose = CameraOrbitPose(yaw: angles.yaw, pitch: angles.pitch, distance: distance, target: target)
            if lineOfSight(pose.eye, note) { return pose }
        }
        return nil
    }

    /// Yaw offsets (degrees), in preference order, tried around the room-interior
    /// direction when the line of sight to the note is blocked.
    static let yawOffsets: [Float] = [0, 30, -30, 60, -60, 90, -90, 135, -135, 180]

    /// Angle from the orbit `target` to the `eye` for a desired `target → eye`
    /// direction, clamped to the viewer's pitch limits.
    ///
    /// `fallbackYaw` is used when the direction is (nearly) vertical and its
    /// horizontal component cannot define a yaw.
    static func orbitAngles(
        forDirection direction: SIMD3<Float>,
        minPitch: Float,
        maxPitch: Float,
        fallbackYaw: Float
    ) -> (yaw: Float, pitch: Float) {
        let normalized = normalizedOrFallback(direction, fallback: SIMD3<Float>(0, 0, 1))
        let unitY = min(1, max(-1, normalized.y))
        let pitch = min(maxPitch, max(minPitch, asin(unitY)))
        let horizontalLength = (normalized.x * normalized.x + normalized.z * normalized.z).squareRoot()
        let yaw = horizontalLength > 0.0001 ? atan2(normalized.x, normalized.z) : fallbackYaw
        return (yaw, pitch)
    }

    /// Candidate `target → eye` directions in preference order:
    /// the current on-screen direction (so an already-usable view is preserved),
    /// then the room-interior direction, then a ring of yaw offsets around it.
    static func candidateDirections(
        inward: SIMD3<Float>,
        current: SIMD3<Float>?,
        elevation: Float
    ) -> [SIMD3<Float>] {
        let interior = normalizedOrFallback(inward, fallback: current ?? SIMD3<Float>(0, 0, 1))
        let elevated = interiorCandidate(inward: inward, current: current, elevation: elevation)

        var candidates: [SIMD3<Float>] = []
        if let current, simd_length(current) > 0.0001 {
            candidates.append(normalize(current))
        }
        candidates.append(interior)
        for degrees in yawOffsets {
            let radians = degrees * Float.pi / 180
            candidates.append(rotatedAroundY(elevated, radians: radians))
        }
        return candidates
    }

    /// The room-interior viewing direction (`target → eye`), lifted by `elevation`.
    /// Supplies the elevated search ring in addition to the signed interior direction.
    static func interiorCandidate(
        inward: SIMD3<Float>,
        current: SIMD3<Float>?,
        elevation: Float
    ) -> SIMD3<Float> {
        let fallback = horizontalized(current ?? SIMD3<Float>(0, 0, 1)) ?? SIMD3<Float>(0, 0, 1)
        let base = horizontalized(inward) ?? fallback
        return applyElevation(base, elevation: elevation)
    }

    /// Unit vector from `origin` toward `destination`, or nil when they coincide.
    static func direction(from origin: SIMD3<Float>, to destination: SIMD3<Float>) -> SIMD3<Float>? {
        let delta = destination - origin
        let length = simd_length(delta)
        guard length > 0.0001 else { return nil }
        return delta / length
    }

    /// Unit `offsetFromTarget` vector for the given orbit angles.
    static func offsetDirection(yaw: Float, pitch: Float) -> SIMD3<Float> {
        let horizontal = cos(pitch)
        return SIMD3<Float>(
            horizontal * sin(yaw),
            sin(pitch),
            horizontal * cos(yaw)
        )
    }

    private static func horizontalized(_ direction: SIMD3<Float>) -> SIMD3<Float>? {
        let flattened = SIMD3<Float>(direction.x, 0, direction.z)
        let length = simd_length(flattened)
        guard length > 0.0001 else { return nil }
        return flattened / length
    }

    private static func applyElevation(_ horizontalDirection: SIMD3<Float>, elevation: Float) -> SIMD3<Float> {
        let horizontalScale = cos(elevation)
        return SIMD3<Float>(
            horizontalDirection.x * horizontalScale,
            sin(elevation),
            horizontalDirection.z * horizontalScale
        )
    }

    private static func rotatedAroundY(_ direction: SIMD3<Float>, radians: Float) -> SIMD3<Float> {
        let cosine = cos(radians)
        let sine = sin(radians)
        return SIMD3<Float>(
            direction.x * cosine + direction.z * sine,
            direction.y,
            -direction.x * sine + direction.z * cosine
        )
    }

    private static func normalizedOrFallback(_ direction: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(direction)
        guard length > 0.0001 else { return fallback }
        return direction / length
    }
}
