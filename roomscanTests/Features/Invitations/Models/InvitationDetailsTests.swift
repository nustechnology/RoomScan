//
//  InvitationDetailsTests.swift
//  roomscanTests
//

@testable import roomscan
import Testing

struct InvitationDetailsTests {
    @Test func memberwiseInitDefaultsLinkTypeToInvitation() {
        let details = InvitationDetails(
            token: "token",
            scope: .project,
            title: "Shared Project",
            ownerName: "Owner",
            invitedEmail: nil,
            existingAccessDestination: nil,
            itemCount: 0,
            showsThumbnail: false,
            project: nil,
            scan: nil
        )

        #expect(details.type == .invitation)
    }

    @Test func memberwiseInitAcceptsExplicitShareLinkType() {
        let details = InvitationDetails(
            token: "token",
            scope: .scan,
            type: .shareLink,
            title: "Shared Scan",
            ownerName: "Owner",
            invitedEmail: nil,
            existingAccessDestination: nil,
            itemCount: 0,
            showsThumbnail: false,
            project: nil,
            scan: nil
        )

        #expect(details.type == .shareLink)
    }
}
