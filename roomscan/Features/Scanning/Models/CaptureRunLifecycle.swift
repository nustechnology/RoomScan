//
//  CaptureRunLifecycle.swift
//  roomscan
//

nonisolated struct CaptureRunLifecycle: Equatable, Sendable {
    private(set) var runGeneration = 0
    private(set) var lastStopGeneration: Int?
    private(set) var isWaitingForStopCallback = false
    private(set) var isStartQueued = false
    private(set) var hasUnconsumedTerminal = false

    enum StartDecision: Equatable {
        case beginNow
        case queueUntilPreviousStop
    }

    enum StopDecision: Equatable {
        case waitForCallback
        case alreadyEnded
    }

    enum TerminalDecision: Equatable {
        case ignoreStale
        case expectedStop
        case expectedStopThenBeginQueuedRun
        case unexpectedEnd
    }

    mutating func requestStart() -> StartDecision {
        if isWaitingForStopCallback {
            isStartQueued = true
            return .queueUntilPreviousStop
        }
        beginRun()
        return .beginNow
    }

    mutating func requestStop() -> StopDecision {
        lastStopGeneration = runGeneration
        if hasUnconsumedTerminal {
            hasUnconsumedTerminal = false
            lastStopGeneration = nil
            isWaitingForStopCallback = false
            return .alreadyEnded
        }
        isWaitingForStopCallback = true
        return .waitForCallback
    }

    mutating func noteTerminalReceived() {
        hasUnconsumedTerminal = true
    }

    mutating func markRunLive() {
        hasUnconsumedTerminal = false
    }

    /// Callback from a replaced capture session. Settles that session's in-flight
    /// stop; otherwise ignored so it cannot end the live run.
    mutating func handleStaleTerminal() -> TerminalDecision {
        guard isWaitingForStopCallback else {
            return .ignoreStale
        }
        return handleTerminalCallback()
    }

    mutating func handleTerminalCallback() -> TerminalDecision {
        hasUnconsumedTerminal = false
        if let lastStop = lastStopGeneration, lastStop < runGeneration {
            lastStopGeneration = nil
            isWaitingForStopCallback = false
            return .ignoreStale
        }

        let queuedStart = isStartQueued
        isStartQueued = false
        isWaitingForStopCallback = false

        if lastStopGeneration == runGeneration {
            lastStopGeneration = nil
            if queuedStart {
                beginRun()
                return .expectedStopThenBeginQueuedRun
            }
            return .expectedStop
        }

        if queuedStart {
            beginRun()
            return .expectedStopThenBeginQueuedRun
        }
        return .unexpectedEnd
    }

    private mutating func beginRun() {
        runGeneration += 1
        hasUnconsumedTerminal = false
    }
}
