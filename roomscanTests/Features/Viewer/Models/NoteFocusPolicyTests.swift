import Foundation
@testable import roomscan
import simd
import Testing

struct NoteFocusPolicyTests {
    private let start = CameraOrbitPose(yaw: 0, pitch: 0.38, distance: 6.5, target: .zero)

    @Test func tightClearanceNeverExpandsPastSurface() {
        #expect(NoteFocusSolver.safeDistance(surfaceDistance: 2.0) == nil)
        #expect(NoteFocusSolver.safeDistance(surfaceDistance: 2.5) == nil)
        #expect(NoteFocusSolver.safeDistance(surfaceDistance: .nan) == nil)
        #expect(NoteFocusSolver.safeDistance(surfaceDistance: nil) == NoteFocusSolver.preferredDistance)
    }

    @Test func offsetIsIncludedBeforeApplyingSafetyMargin() throws {
        // A hit 2.90m from the shifted ray origin is 2.95m from the target.
        let hitDistance: Float = 2.90
        #expect(NoteFocusSolver.safeDistance(surfaceDistance: hitDistance) == nil)
        let distance = try #require(NoteFocusSolver.safeDistance(
            surfaceDistance: hitDistance + NoteFocusSolver.rayOriginOffset
        ))
        #expect(distance >= CameraOrbitLimits.minDistance)
        #expect(distance < hitDistance + NoteFocusSolver.rayOriginOffset)
        #expect(NoteFocusSolver.safeDistance(surfaceDistance: 2.89 + NoteFocusSolver.rayOriginOffset) == nil)
    }

    @Test func insufficientClearanceSkipsLOSAndReturnsNoFallback() {
        var losCalls = 0
        let pose = NoteFocusSolver.resolve(
            note: .zero, displayedPose: start, roomCenter: [0, 0, -3],
            surfaceDistance: { _, _ in 1 },
            lineOfSight: { _, _ in losCalls += 1; return true }
        )
        #expect(pose == nil)
        #expect(losCalls == 0)
    }

    @Test func blockedCurrentViewSelectsNextVisibleCandidateAndStops() throws {
        var queries = 0
        var losCalls = 0
        let pose = try #require(NoteFocusSolver.resolve(
            note: .zero, displayedPose: start, roomCenter: [0, -2, -3],
            surfaceDistance: { _, _ in queries += 1; return nil },
            lineOfSight: { _, _ in losCalls += 1; return losCalls == 2 }
        ))
        #expect(queries == 2)
        #expect(losCalls == 2)
        #expect(pose.eye.y < pose.target.y)
        #expect(pose.eye.z < pose.target.z)
    }

    @Test func allOccludedCandidatesReturnNilWithoutExtraFallbackQuery() {
        var queries = 0
        var losCalls = 0
        let pose = NoteFocusSolver.resolve(
            note: .zero, displayedPose: start, roomCenter: [0, 0, -3],
            surfaceDistance: { _, _ in queries += 1; return nil },
            lineOfSight: { _, _ in losCalls += 1; return false }
        )
        #expect(pose == nil)
        #expect(queries == losCalls)
        #expect(queries > 0)
    }

    @Test func missingCenterUsesDisplayedOrbitDirection() throws {
        var losCalls = 0
        let pose = try #require(NoteFocusSolver.resolve(
            note: [2, 1, 0], displayedPose: start, roomCenter: nil,
            surfaceDistance: { _, _ in nil },
            lineOfSight: { _, _ in losCalls += 1; return losCalls == 2 }
        ))
        #expect(simd_length(normalize(pose.offsetFromTarget) + start.forward) < 0.0001)
    }

    @Test func topViewFocusPreservesAnglesAndCapsDistance() {
        let top = CameraOrbitPose(yaw: 0, pitch: CameraOrbitLimits.maxPitch, distance: 8.5, target: .zero)
        let pose = NoteFocusSolver.topViewPose(from: top, note: [1, 2, 3])
        #expect(pose.yaw == top.yaw)
        #expect(pose.pitch == top.pitch)
        #expect(pose.target == SIMD3<Float>(1, 2, 3))
        #expect(pose.distance == 5.5)
        var close = top
        close.distance = 2.5
        #expect(NoteFocusSolver.topViewPose(from: close, note: .zero).distance == 2.5)
    }

    @Test func downwardFocusRemainsValidForSubsequentDragAndZoom() throws {
        var losCalls = 0
        let pose = try #require(NoteFocusSolver.resolve(
            note: [0, 3, 0], displayedPose: start, roomCenter: [0, 0, -3],
            surfaceDistance: { _, _ in 3 },
            lineOfSight: { _, _ in losCalls += 1; return losCalls == 2 }
        ))
        #expect(pose.pitch < 0)
        #expect(abs(CameraOrbitLimits.clampedPitch(pose.pitch + 0.01) - pose.pitch - 0.01) < 0.0001)
        #expect(CameraOrbitLimits.clampedDistance(pose.distance) == pose.distance)
        #expect(CameraOrbitLimits.clampedDistance(pose.distance * 0.82) <= pose.distance)
        #expect(CameraOrbitLimits.clampedDistance(pose.distance / 1.01) <= pose.distance)
    }

    @Test func lineOfSightAcceptsAttachmentSurfaceButRejectsEarlierOccluder() {
        #expect(NoteFocusSolver.hasClearLineOfSight(hitDistance: nil, targetDistance: 3))
        #expect(NoteFocusSolver.hasClearLineOfSight(hitDistance: 3, targetDistance: 3))
        #expect(NoteFocusSolver.hasClearLineOfSight(hitDistance: 2.95, targetDistance: 3))
        #expect(!NoteFocusSolver.hasClearLineOfSight(hitDistance: 2.8, targetDistance: 3))
        #expect(!NoteFocusSolver.hasClearLineOfSight(hitDistance: .nan, targetDistance: 3))
    }
}
