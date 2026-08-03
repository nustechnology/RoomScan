//
//  ModelPreviewCameraTests.swift
//  roomscanTests
//

import simd
import XCTest
@testable import roomscan

final class ModelPreviewCameraTests: XCTestCase {
    private let accuracy: Float = 0.0001
    private let pivot = SIMD3<Float>(1, 2, 3)
    private let framing = ModelPreviewFraming(pivot: SIMD3<Float>(1, 2, 3), extent: 4)

    // MARK: - Deriving a pose from the live camera

    func testPoseDerivedFromEye_roundTripsBackToTheSamePosition() {
        let eye = SIMD3<Float>(4.2, 5.5, -1.3)

        let pose = ModelPreviewCameraPose(eye: eye, pivot: pivot)

        assertEqual(pose.eye(around: pivot), eye)
    }

    func testPoseDerivedFromEye_reportsDistanceToPivot() {
        let eye = pivot + SIMD3<Float>(0, 0, 7)

        let pose = ModelPreviewCameraPose(eye: eye, pivot: pivot)

        XCTAssertEqual(pose.distance, 7, accuracy: accuracy)
        XCTAssertEqual(pose.yaw, 0, accuracy: accuracy)
        XCTAssertEqual(pose.pitch, 0, accuracy: accuracy)
    }

    func testPoseDerivedFromEyeAtPivot_staysFiniteInsteadOfDividingByZero() {
        let pose = ModelPreviewCameraPose(eye: pivot, pivot: pivot)

        XCTAssertGreaterThan(pose.distance, 0)
        XCTAssertTrue(pose.pitch.isFinite)
        XCTAssertTrue(pose.yaw.isFinite)
        XCTAssertTrue(pose.eye(around: pivot).x.isFinite)
    }

    // MARK: - Rotation

    func testRotate_keepsElevationAndDistance() {
        let pose = ModelPreviewCameraPose(eye: SIMD3<Float>(4.2, 5.5, -1.3), pivot: pivot)

        let rotated = pose.rotated(by: .pi / 4)

        XCTAssertEqual(rotated.pitch, pose.pitch, accuracy: accuracy)
        XCTAssertEqual(rotated.distance, pose.distance, accuracy: accuracy)
        XCTAssertNotEqual(rotated.eye(around: pivot), pose.eye(around: pivot))
    }

    /// A rotation command must continue from wherever a gesture left the camera, so eight
    /// quarter-turns applied through the live position return to the starting point.
    func testRotate_appliedThroughLivePosition_returnsToStartAfterFullTurn() {
        let start = SIMD3<Float>(4.2, 5.5, -1.3)
        var eye = start

        for _ in 0..<8 {
            let pose = ModelPreviewCameraPose(eye: eye, pivot: pivot)
            eye = pose.rotated(by: .pi / 4).eye(around: pivot)
        }

        assertEqual(eye, start, accuracy: 0.001)
    }

    func testRotate_afterManualGesture_orbitsTheGesturedPoseNotTheInitialOne() {
        let gesturedEye = framing.initialPose.eye(around: pivot) + SIMD3<Float>(2.5, -1.5, 0.75)
        let gesturedPose = ModelPreviewCameraPose(eye: gesturedEye, pivot: pivot)

        let rotated = gesturedPose.rotated(by: .pi / 4)

        XCTAssertEqual(rotated.distance, gesturedPose.distance, accuracy: accuracy)
        XCTAssertEqual(rotated.pitch, gesturedPose.pitch, accuracy: accuracy)
        XCTAssertNotEqual(rotated.distance, framing.initialPose.distance, accuracy: accuracy)
        XCTAssertNotEqual(rotated.pitch, framing.initialPose.pitch, accuracy: accuracy)
    }

    // MARK: - Zoom

    func testZoomIn_movesCloserWhileKeepingOrientation() {
        let pose = ModelPreviewCameraPose(eye: SIMD3<Float>(4.2, 5.5, -1.3), pivot: pivot)

        let zoomed = pose.zoomed(by: 0.84, limits: framing.distanceLimits)

        XCTAssertEqual(zoomed.distance, pose.distance * 0.84, accuracy: accuracy)
        XCTAssertEqual(zoomed.yaw, pose.yaw, accuracy: accuracy)
        XCTAssertEqual(zoomed.pitch, pose.pitch, accuracy: accuracy)
    }

    func testZoomInThenZoomOut_returnsToTheOriginalDistance() {
        let pose = framing.initialPose
        let limits = framing.distanceLimits

        let restored = pose
            .zoomed(by: 0.84, limits: limits)
            .zoomed(by: 1 / 0.84, limits: limits)

        XCTAssertEqual(restored.distance, pose.distance, accuracy: 0.001)
    }

    func testZoomIn_clampsAtTheClosestAllowedDistance() {
        let limits = framing.distanceLimits
        let pose = ModelPreviewCameraPose(yaw: 0, pitch: 0, distance: limits.lowerBound)

        let zoomed = pose.zoomed(by: 0.5, limits: limits)

        XCTAssertEqual(zoomed.distance, limits.lowerBound, accuracy: accuracy)
    }

    func testZoomOut_clampsAtTheFarthestAllowedDistance() {
        let limits = framing.distanceLimits
        let pose = ModelPreviewCameraPose(yaw: 0, pitch: 0, distance: limits.upperBound)

        let zoomed = pose.zoomed(by: 2, limits: limits)

        XCTAssertEqual(zoomed.distance, limits.upperBound, accuracy: accuracy)
    }

    /// Zooming is relative to the live camera, so a pinch beyond the limits is pulled back
    /// into range by the next zoom command rather than being ignored.
    func testZoom_fromBeyondTheLimits_isPulledBackIntoRange() {
        let limits = framing.distanceLimits
        let pinchedTooClose = ModelPreviewCameraPose(
            yaw: 0,
            pitch: 0,
            distance: limits.lowerBound / 4
        )

        let zoomedOut = pinchedTooClose.zoomed(by: 1 / 0.84, limits: limits)

        XCTAssertEqual(zoomedOut.distance, limits.lowerBound, accuracy: accuracy)
    }

    // MARK: - Framing

    func testInitialPose_framesTheModelAboveAndInFrontOfItsCenter() {
        let eye = framing.initialPose.eye(around: framing.pivot)

        XCTAssertEqual(eye.x, framing.pivot.x, accuracy: accuracy)
        XCTAssertGreaterThan(eye.y, framing.pivot.y)
        XCTAssertGreaterThan(eye.z, framing.pivot.z)
    }

    func testInitialPose_sitsInsideTheZoomLimits() {
        let limits = framing.distanceLimits

        XCTAssertTrue(limits.contains(framing.initialPose.distance))
    }

    func testFraming_keepsSmallModelsAtAWorkableDistance() {
        let tiny = ModelPreviewFraming(pivot: .zero, extent: 0)

        XCTAssertGreaterThan(tiny.initialPose.distance, 0)
        XCTAssertLessThan(tiny.initialPose.distance, framing.initialPose.distance)
    }

    // MARK: - Helpers

    private func assertEqual(
        _ lhs: SIMD3<Float>,
        _ rhs: SIMD3<Float>,
        accuracy: Float? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance = accuracy ?? self.accuracy
        XCTAssertEqual(lhs.x, rhs.x, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: tolerance, file: file, line: line)
    }
}
