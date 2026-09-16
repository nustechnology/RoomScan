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

struct InvitationLinkTypeParsingTests {
    @Test func parsesKnownSpellings() {
        #expect(InvitationLinkType.parse("invitation") == .invitation)
        #expect(InvitationLinkType.parse("INVITATION") == .invitation)
        #expect(InvitationLinkType.parse("share-link") == .shareLink)
        #expect(InvitationLinkType.parse("SHARE_LINK") == .shareLink)
        #expect(InvitationLinkType.parse("shareLink") == .shareLink)
        #expect(InvitationLinkType.parse("  share-link  ") == .shareLink)
    }

    @Test func rejectsEmptyAndUnknownValues() {
        #expect(InvitationLinkType.parse("") == nil)
        #expect(InvitationLinkType.parse("   ") == nil)
        #expect(InvitationLinkType.parse("unknown-type") == nil)
    }
}
