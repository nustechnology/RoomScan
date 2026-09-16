//
//  PresentationHandoff.swift
//  roomscan
//

import Foundation

/// Generation token so a newer post-dismiss presentation supersedes an in-flight one.
struct PresentationFlight: Equatable {
    private(set) var generation = 0

    /// Cancels conceptual ownership of any prior flight and returns the new generation.
    mutating func begin() -> Int {
        generation &+= 1
        return generation
    }

    /// Whether `flightGeneration` is still the active handoff.
    func isCurrent(_ flightGeneration: Int) -> Bool {
        flightGeneration == generation
    }
}

/// Shared post-cover presentation sequencing used by scan-flow and owner-action handoffs.
enum PresentationHandoff {
    /// Defers one turn, assigns once, yields again, then assigns a second time.
    ///
    /// Presenting from within another cover's `onDismiss` is dropped in the same main-actor
    /// turn. The second assign retries only when the first assignment was rejected.
    ///
    /// `isCurrent` must become false when a newer handoff supersedes this run.
    @MainActor
    static func presentAfterDismiss(
        isCurrent: @MainActor () -> Bool = { true },
        yield: @MainActor () async -> Void = { await Task.yield() },
        assign: @MainActor () -> Void
    ) async {
        await yield()
        guard isCurrent() else { return }
        assign()

        await yield()
        guard isCurrent() else { return }
        assign()
    }
}
