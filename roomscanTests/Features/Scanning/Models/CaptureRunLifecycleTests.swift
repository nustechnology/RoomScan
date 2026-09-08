//
//  CaptureRunLifecycleTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

final class CaptureRunLifecycleTests: XCTestCase {
    func testStopThenStart_defersNewRunUntilTerminalCallback() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        lifecycle.requestStop()
        XCTAssertEqual(lifecycle.requestStart(), .queueUntilPreviousStop)
        XCTAssertEqual(lifecycle.runGeneration, 1)

        XCTAssertEqual(lifecycle.handleTerminalCallback(), .expectedStopThenBeginQueuedRun)
        XCTAssertEqual(lifecycle.runGeneration, 2)
        XCTAssertFalse(lifecycle.isWaitingForStopCallback)
        XCTAssertFalse(lifecycle.isStartQueued)
    }

    func testLateTerminalFromReplacedSessionAfterRestart_isIgnored() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.requestStop(), .waitForCallback)
        XCTAssertEqual(lifecycle.handleTerminalCallback(), .expectedStop)
        XCTAssertEqual(lifecycle.requestStart(), .beginNow)

        XCTAssertEqual(lifecycle.handleStaleTerminal(), .ignoreStale)
        XCTAssertEqual(lifecycle.runGeneration, 2)
        XCTAssertFalse(lifecycle.isWaitingForStopCallback)
    }

    func testCurrentSessionEndAfterCompletedRestart_isUnexpected() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.requestStop(), .waitForCallback)
        XCTAssertEqual(lifecycle.handleTerminalCallback(), .expectedStop)
        XCTAssertEqual(lifecycle.requestStart(), .beginNow)

        XCTAssertEqual(lifecycle.handleTerminalCallback(), .unexpectedEnd)
    }

    func testStaleTerminalWhileWaitingForStop_settlesExpectedStop() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.requestStop(), .waitForCallback)

        XCTAssertEqual(lifecycle.handleStaleTerminal(), .expectedStop)
        XCTAssertFalse(lifecycle.isWaitingForStopCallback)
    }

    func testStaleTerminalWhileWaitingForStop_beginsQueuedRun() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.requestStop(), .waitForCallback)
        XCTAssertEqual(lifecycle.requestStart(), .queueUntilPreviousStop)

        XCTAssertEqual(lifecycle.handleStaleTerminal(), .expectedStopThenBeginQueuedRun)
        XCTAssertEqual(lifecycle.runGeneration, 2)
        XCTAssertFalse(lifecycle.isWaitingForStopCallback)
        XCTAssertFalse(lifecycle.isStartQueued)
    }

    func testUnexpectedEndOnLiveRun_isUnexpected() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.handleTerminalCallback(), .unexpectedEnd)
    }

    func testPausedTerminalThenStop_doesNotWaitForAnotherCallback() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        lifecycle.noteTerminalReceived()

        XCTAssertEqual(lifecycle.requestStop(), .alreadyEnded)
        XCTAssertFalse(lifecycle.isWaitingForStopCallback)
        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.runGeneration, 2)
    }

    func testPausedTerminalThenLiveUpdate_stopWaitsForCallback() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        lifecycle.noteTerminalReceived()
        lifecycle.markRunLive()

        XCTAssertEqual(lifecycle.requestStop(), .waitForCallback)
        XCTAssertTrue(lifecycle.isWaitingForStopCallback)
    }

    func testExpectedStopWithoutRestart() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        lifecycle.requestStop()
        XCTAssertEqual(lifecycle.handleTerminalCallback(), .expectedStop)
        XCTAssertEqual(lifecycle.runGeneration, 1)
    }

    func testStopBeforeLiveSession_settlesThenStartBeginsNow() {
        var lifecycle = CaptureRunLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.requestStop(), .waitForCallback)
        XCTAssertEqual(lifecycle.handleTerminalCallback(), .expectedStop)
        XCTAssertFalse(lifecycle.isWaitingForStopCallback)
        XCTAssertEqual(lifecycle.requestStart(), .beginNow)
        XCTAssertEqual(lifecycle.runGeneration, 2)
    }
}
