//
//  CameraOrbitPoseTests.swift
//  roomscanTests
//
//  Device QA (manual): open a real USDZ in the viewer, tap 3D/Top 2–3×/s for ~5s;
//  camera must settle on the last mode. Then orbit, pinch, pan, reset, and zoom
//  mid-transition; also try note drag and fullscreen. If gestures also freeze,
//  investigate renderer (clipShape/Metal), not orbit animation.
//

import Foundation
@testable import roomscan
import simd
import Testing

struct CameraOrbitPoseTests {
    private let start = CameraOrbitPose(
        yaw: 0.55,
        pitch: 0.38,
        distance: 6.5,
        target: SIMD3<Float>(0, 1, 0)
    )
    private let topView = CameraOrbitPose(
        yaw: 0,
        pitch: (.pi / 2) - 0.06,
        distance: 8.5,
        target: SIMD3<Float>(0, 1, 0)
    )

    @Test func gesturePitchStaysAboveTargetFromDefaultOrbit() {
        let minimum = CameraOrbitLimits.gestureMinimumPitch(startingAt: start.pitch)
        let pitch = CameraOrbitLimits.clampedGesturePitch(-0.5, minimumPitch: minimum)
        #expect(pitch == CameraOrbitLimits.minGesturePitch)
    }

    @Test func gestureKeepsFocusedNegativePitchWithoutLoweringIt() {
        let focusedPitch: Float = -0.42
        let minimum = CameraOrbitLimits.gestureMinimumPitch(startingAt: focusedPitch)
        #expect(minimum == focusedPitch)
        #expect(CameraOrbitLimits.clampedGesturePitch(-0.8, minimumPitch: minimum) == focusedPitch)
        #expect(CameraOrbitLimits.clampedGesturePitch(-0.3, minimumPitch: minimum) == -0.3)
    }

    @Test func offsetFromTargetMatchesYawPitchDistance() {
        let expectedOffset = SIMD3<Float>(
            start.distance * cos(start.pitch) * sin(start.yaw),
            start.distance * sin(start.pitch),
            start.distance * cos(start.pitch) * cos(start.yaw)
        )
        let offset = start.offsetFromTarget
        #expect(abs(offset.x - expectedOffset.x) < 0.0001)
        #expect(abs(offset.y - expectedOffset.y) < 0.0001)
        #expect(abs(offset.z - expectedOffset.z) < 0.0001)
        #expect(abs(simd_length(offset) - start.distance) < 0.0001)
        #expect(start.eye == start.target + expectedOffset)
    }

    @Test func panRightIsHorizontalAndPerpendicularToForward() {
        let right = start.panRight
        let forward = start.forward
        #expect(abs(right.y) < 0.0001)
        #expect(abs(simd_dot(right, forward)) < 0.0001)
        #expect(abs(simd_length(right) - 1) < 0.0001)
    }

    @Test func lerpAtZeroReturnsStart() {
        let pose = CameraOrbitPose.lerp(from: start, to: topView, progress: 0)
        #expect(pose == start)
    }

    @Test func lerpAtOneReturnsEnd() {
        let pose = CameraOrbitPose.lerp(from: start, to: topView, progress: 1)
        #expect(abs(pose.yaw - topView.yaw) < 0.0001)
        #expect(abs(pose.pitch - topView.pitch) < 0.0001)
        #expect(abs(pose.distance - topView.distance) < 0.0001)
        #expect(pose.target == topView.target)
    }

    @Test func lerpMidpointIsBetweenStartAndEnd() {
        let pose = CameraOrbitPose.lerp(from: start, to: topView, progress: 0.5)
        #expect(pose.yaw > topView.yaw && pose.yaw < start.yaw)
        #expect(pose.pitch > start.pitch && pose.pitch < topView.pitch)
        #expect(pose.distance > start.distance && pose.distance < topView.distance)
    }

    @Test func interruptContinuesFromMidPoseTowardNewEnd() {
        let mid = CameraOrbitPose.lerp(from: start, to: topView, progress: 0.4)
        let resumed = CameraOrbitPose.lerp(from: mid, to: start, progress: 1)
        #expect(abs(resumed.yaw - start.yaw) < 0.0001)
        #expect(abs(resumed.pitch - start.pitch) < 0.0001)
        #expect(abs(resumed.distance - start.distance) < 0.0001)
    }

    @Test func yawLerpTakesShortestPathAcrossWrap() {
        let nearPi = CameraOrbitPose(
            yaw: Float.pi - 0.1,
            pitch: 0.38,
            distance: 6.5,
            target: .zero
        )
        let pastNegPi = CameraOrbitPose(
            yaw: -Float.pi + 0.1,
            pitch: 0.38,
            distance: 6.5,
            target: .zero
        )
        let mid = CameraOrbitPose.lerp(from: nearPi, to: pastNegPi, progress: 0.5)
        // Shortest path crosses ±π (~0.2 rad total), not the long way around.
        #expect(abs(mid.yaw) > Float.pi - 0.15)
    }

    @Test func yawLerpTakesShortestPathPastOneFullTurn() {
        let manyTurns = CameraOrbitPose(
            yaw: Float.pi * 4 + 0.2,
            pitch: 0.38,
            distance: 6.5,
            target: .zero
        )
        let zero = CameraOrbitPose(yaw: 0, pitch: 0.38, distance: 6.5, target: .zero)
        let mid = CameraOrbitPose.lerp(from: manyTurns, to: zero, progress: 0.5)
        // Shortest path is -0.2 rad, so the midpoint stays near the start's turn, not halfway around.
        #expect(abs(mid.yaw - Float.pi * 4) < 0.15)
    }

    @Test func easeInOutIsSlowAtStartAndEnd() {
        let timing = CameraMotionTiming.easeInOut
        let early = timing.progress(linear: 0.1)
        let late = timing.progress(linear: 0.9)
        #expect(early < 0.1)
        #expect(late > 0.9)
        #expect(abs(timing.progress(linear: 0) - 0) < 0.0001)
        #expect(abs(timing.progress(linear: 1) - 1) < 0.0001)
    }

    @Test func easeOutMovesImmediately() {
        let timing = CameraMotionTiming.easeOut
        let early = timing.progress(linear: 0.1)
        #expect(early > 0.1)
        #expect(abs(timing.progress(linear: 0) - 0) < 0.0001)
        #expect(abs(timing.progress(linear: 1) - 1) < 0.0001)
    }
}
