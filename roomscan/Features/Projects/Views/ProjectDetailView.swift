//
//  ProjectDetailView.swift
//  roomscan
//

import SwiftUI

struct ProjectDetailView: View {
    let project: ProjectSummary
    var accessPolicy: DetailAccessPolicy = .editable

    @Environment(\.dismiss) private var dismiss
    @State private var viewerInput: ViewerInput?

    private var showsOwnerActions: Bool {
        ProjectDetailPresentation.showsOwnerActions(for: accessPolicy)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    projectMetadata

                    Text(scansTitle)
                        .font(.title3.bold())
                        .padding(.top, 24)
                        .padding(.bottom, 14)
                        .accessibilityIdentifier("projects.detail.scanCount.\(project.id)")

                    VStack(spacing: 0) {
                        if project.roomScans.isEmpty {
                            Text("projects.detail.emptyScans.message")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 28)
                                .accessibilityIdentifier("projects.detail.emptyScans")
                        } else {
                            ForEach(Array(project.roomScans.enumerated()), id: \.element.id) { index, scan in
                                RoomScanRowView(
                                    scan: scan,
                                    onTap: {
                                        viewerInput = ViewerInput(
                                            scanID: scan.id,
                                            scanName: scan.name,
                                            modelURL: scan.localModelURL
                                        )
                                    }
                                )
                                    .padding(12)

                                if index < project.roomScans.count - 1 {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.secondary.opacity(0.35), lineWidth: 1)
                    }

                    if showsOwnerActions {
                        VStack(spacing: 12) {
                            PrimaryActionButton(
                                title: String(localized: "projects.detail.addScan"),
                                systemImageName: "plus",
                                color: .white,
                                action: {},
                                foregroundColor: .primary,
                                borderColor: .secondary.opacity(0.35),
                                cornerRadius: 16,
                                accessibilityIdentifier: "projects.detail.addScan"
                            )

                            PrimaryActionButton(
                                title: String(localized: "projects.detail.shareProject"),
                                systemImageName: "square.and.arrow.up",
                                color: .white,
                                action: {},
                                foregroundColor: .primary,
                                borderColor: .secondary.opacity(0.35),
                                cornerRadius: 16,
                                accessibilityIdentifier: "projects.detail.shareProject"
                            )
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }
            .background(.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(String(localized: "common.back"))
                    .accessibilityIdentifier("projects.detail.close")
                }

                ToolbarItem(placement: .principal) {
                    Text(project.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .accessibilityIdentifier("projects.detail.title.\(project.id)")
                }
            }
            .accessibilityIdentifier("projects.detail")
            .fullScreenCover(item: $viewerInput) { input in
                ViewerView(
                    input: input,
                    notesService: MockNotesService.shared,
                    onBack: { viewerInput = nil }
                )
            }
        }
        .background(.white)
    }

    private var projectMetadata: some View {
        VStack(spacing: 0) {
            DetailMetadataRow(
                title: String(localized: "projects.detail.metadata.owner"),
                value: project.ownerName,
                accessibilityIdentifier: "projects.detail.metadata.owner"
            )
            metadataDivider
            DetailMetadataRow(
                title: String(localized: "projects.detail.metadata.created"),
                value: createdDateText,
                accessibilityIdentifier: "projects.detail.metadata.created"
            )
            metadataDivider
            DetailMetadataRow(
                title: String(localized: "projects.detail.metadata.shared"),
                value: sharedUserCountText,
                showsDisclosure: showsOwnerActions,
                accessibilityIdentifier: "projects.detail.metadata.shared",
                action: showsOwnerActions ? {} : nil
            )
            metadataDivider
        }
    }

    private var createdDateText: String {
        ProjectDetailPresentation.createdDateText(for: project.createdAt)
    }

    private var sharedUserCountText: String {
        ProjectDetailPresentation.sharedUserCountText(for: project.sharedUserCount)
    }

    private var scansTitle: String {
        ProjectDetailPresentation.scansTitle(for: project.roomScans.count)
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.45))
            .frame(height: 1)
    }
}

enum ProjectDetailPresentation {
    static func showsOwnerActions(for accessPolicy: DetailAccessPolicy) -> Bool {
        accessPolicy.allowsOwnerActions
    }

    static func createdDateText(for date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().locale(locale))
    }

    static func sharedUserCountText(for count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "projects.detail.sharedUsers.count.format"),
            count
        )
    }

    static func scansTitle(for count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "projects.detail.scans.title.format"),
            count
        )
    }
}

private struct DetailMetadataRow: View {
    let title: String
    let value: String
    var showsDisclosure = false
    var accessibilityIdentifier: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 14)
        .applyAccessibilityIdentifier(accessibilityIdentifier)
    }

    private var rowContent: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func applyAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
