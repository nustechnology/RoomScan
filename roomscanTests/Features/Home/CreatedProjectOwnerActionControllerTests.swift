//
//  CreatedProjectOwnerActionControllerTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest

@MainActor
final class CreatedProjectOwnerActionControllerTests: XCTestCase {
    private let project = ProjectSummary.testFixture()

    func testBegin_whenDetailNotPresented_stagesThenPresentsImmediately() async {
        let controller = CreatedProjectOwnerActionController()
        var dismissed = false

        let task = controller.begin(.edit(project), detailIsPresented: false) {
            dismissed = true
        }

        XCTAssertFalse(dismissed)
        await task?.value

        XCTAssertEqual(controller.activeEdit, project)
        XCTAssertEqual(controller.pending, .edit(project))
    }

    func testBegin_whenDetailPresented_dismissesDetailThenPresentsOnDismiss() async {
        let controller = CreatedProjectOwnerActionController()
        var dismissed = false

        let task = controller.begin(.delete(project), detailIsPresented: true) {
            dismissed = true
        }

        XCTAssertTrue(dismissed)
        XCTAssertNil(task)
        XCTAssertEqual(controller.pending, .delete(project))
        XCTAssertNil(controller.activeDelete)

        await controller.presentAfterDetailDismiss()?.value

        XCTAssertEqual(controller.activeDelete, project)
        XCTAssertEqual(controller.pending, .delete(project))
    }

    func testCancelUnacknowledgedPresentation_dropsStagedDelete() {
        let controller = CreatedProjectOwnerActionController()
        controller.begin(.delete(project), detailIsPresented: true) {}

        controller.cancelUnacknowledgedPresentation()

        XCTAssertNil(controller.pending)
        XCTAssertNil(controller.activeDelete)
        XCTAssertNil(controller.activeEdit)
    }

    func testCancelUnacknowledgedPresentation_leavesAcknowledgedEditCover() async {
        let controller = CreatedProjectOwnerActionController()
        await controller.begin(.edit(project), detailIsPresented: false) {}?.value

        // Simulate the edit cover's `onAppear` acknowledgment.
        controller.pending = nil

        controller.cancelUnacknowledgedPresentation()

        XCTAssertEqual(controller.activeEdit, project)
        XCTAssertNil(controller.pending)
    }

    func testAcknowledgeEditAppeared_clearsPendingKeepsCover() {
        let controller = CreatedProjectOwnerActionController()
        controller.pending = .edit(project)
        controller.activeEdit = project

        controller.acknowledgeEditAppeared(project)

        XCTAssertNil(controller.pending)
        XCTAssertEqual(controller.activeEdit, project)
    }

    func testAcknowledgeDeleteDismissed_clearsPendingKeepsBinding() {
        let controller = CreatedProjectOwnerActionController()
        controller.pending = .delete(project)
        controller.activeDelete = project

        controller.acknowledgeDeleteDismissed()

        XCTAssertNil(controller.pending)
        XCTAssertEqual(controller.activeDelete, project)
    }

    func testPresentAfterDetailDismiss_supersededRunDoesNotOverwrite() async {
        let controller = CreatedProjectOwnerActionController()
        controller.pending = .edit(project)

        let superseded = controller.presentAfterDetailDismiss()
        let current = controller.presentAfterDetailDismiss()

        await superseded?.value
        await current?.value

        XCTAssertEqual(controller.activeEdit, project)
        XCTAssertEqual(controller.pending, .edit(project))
    }
}
