//
//  NoteFocusSolverTests.swift
//  roomscanTests
//

import Foundation
@testable import roomscan
import simd
import Testing

struct NoteFocusSolverTests {
    private let minPitch = CameraOrbitLimits.minPitch
    private let maxPitch = CameraOrbitLimits.maxPitch
    private let tolerance: Float = 0.0001

    @Test func horizontalDirectionRemainsLevel() {
        let angles = NoteFocusSolver.orbitAngles(
            forDirection: SIMD3<Float>(0, 0, 1),
            minPitch: minPitch,
            maxPitch: maxPitch,
            fallbackYaw: 0
        )
        #expect(abs(angles.yaw) < tolerance)
        #expect(abs(angles.pitch) < tolerance)
    }

    @Test func directionMapsToYaw() {
        let angles = NoteFocusSolver.orbitAngles(
            forDirection: SIMD3<Float>(1, 0, 0),
            minPitch: minPitch,
            maxPitch: maxPitch,
            fallbackYaw: 0
        )
        #expect(abs(angles.yaw - .pi / 2) < tolerance)
    }

    @Test func upwardDirectionClampsToMaxPitch() {
        let angles = NoteFocusSolver.orbitAngles(
            forDirection: SIMD3<Float>(0, 1, 0),
            minPitch: minPitch,
            maxPitch: maxPitch,
            fallbackYaw: 0.6
        )
        #expect(abs(angles.pitch - maxPitch) < tolerance)
        #expect(abs(angles.yaw - 0.6) < tolerance)
    }

    @Test func verticalDirectionUsesFallbackYaw() {
        let angles = NoteFocusSolver.orbitAngles(
            forDirection: SIMD3<Float>(0, -1, 0),
            minPitch: minPitch,
            maxPitch: maxPitch,
            fallbackYaw: -1.2
        )
        #expect(abs(angles.yaw - -1.2) < tolerance)
        #expect(abs(angles.pitch - minPitch) < tolerance)
    }

    @Test func zeroDirectionFallsBackToLevelForward() {
        let angles = NoteFocusSolver.orbitAngles(
            forDirection: .zero,
            minPitch: minPitch,
            maxPitch: maxPitch,
            fallbackYaw: 0.4
        )
        #expect(abs(angles.yaw) < tolerance)
        #expect(abs(angles.pitch) < tolerance)
    }

    @Test func candidatesPreferCurrentDirectionThenInward() {
        let current = SIMD3<Float>(0, 0, 1)
        let inward = SIMD3<Float>(0, 0, -1)
        let candidates = NoteFocusSolver.candidateDirections(
            inward: inward,
            current: current,
            elevation: 0.28
        )

        #expect(simd_length(candidates[0] - current) < tolerance)

        #expect(simd_length(candidates[1] - inward) < tolerance)
    }

    @Test func candidatesWithoutCurrentStartWithInward() {
        let inward = SIMD3<Float>(0, 0, -1)
        let candidates = NoteFocusSolver.candidateDirections(
            inward: inward,
            current: nil,
            elevation: 0.28
        )

        #expect(simd_length(candidates[0] - inward) < tolerance)
    }

    @Test func elevatedSearchRemainsAvailableWhenCurrentPresent() {
        let current = SIMD3<Float>(0, 0, 1)
        let inward = SIMD3<Float>(0, 0, -1)
        let candidates = NoteFocusSolver.candidateDirections(
            inward: inward,
            current: current,
            elevation: 0.28
        )
        let interior = NoteFocusSolver.interiorCandidate(
            inward: inward,
            current: current,
            elevation: 0.28
        )
        #expect(candidates.contains { simd_length($0 - interior) < tolerance })
    }

    @Test func elevatedSearchRemainsAvailableWhenCurrentMissing() {
        let inward = SIMD3<Float>(0, 0, -1)
        let candidates = NoteFocusSolver.candidateDirections(
            inward: inward,
            current: nil,
            elevation: 0.28
        )
        let interior = NoteFocusSolver.interiorCandidate(
            inward: inward,
            current: nil,
            elevation: 0.28
        )
        #expect(candidates.contains { simd_length($0 - interior) < tolerance })
    }

    @Test func allCandidatesAreUnitLength() {
        let candidates = NoteFocusSolver.candidateDirections(
            inward: SIMD3<Float>(0.3, -0.8, 0.4),
            current: SIMD3<Float>(0.1, 0.2, 0.9),
            elevation: 0.28
        )
        for candidate in candidates {
            #expect(abs(simd_length(candidate) - 1) < tolerance)
        }
    }

    @Test func verticalInwardStillProducesUnitCandidates() {
        let candidates = NoteFocusSolver.candidateDirections(
            inward: SIMD3<Float>(0, -1, 0),
            current: nil,
            elevation: 0.28
        )
        for candidate in candidates {
            #expect(abs(simd_length(candidate) - 1) < tolerance)
        }
        #expect(candidates.contains { $0.y < 0 })
    }

    @Test func offsetDirectionMatchesOrbitConvention() {
        let forward = NoteFocusSolver.offsetDirection(yaw: 0, pitch: 0)
        #expect(simd_length(forward - SIMD3<Float>(0, 0, 1)) < tolerance)

        let right = NoteFocusSolver.offsetDirection(yaw: .pi / 2, pitch: 0)
        #expect(simd_length(right - SIMD3<Float>(1, 0, 0)) < tolerance)
    }

    @Test func directionReturnsNilWhenPointsCoincide() {
        #expect(NoteFocusSolver.direction(from: .zero, to: .zero) == nil)

        let direction = NoteFocusSolver.direction(
            from: SIMD3<Float>(0, 0, 0),
            to: SIMD3<Float>(0, 0, 4)
        )
        let unwrapped = direction ?? SIMD3<Float>(.nan, .nan, .nan)
        #expect(simd_length(unwrapped - SIMD3<Float>(0, 0, 1)) < tolerance)
    }
}
