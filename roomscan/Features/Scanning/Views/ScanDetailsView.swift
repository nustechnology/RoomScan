//
//  ScanDetailsView.swift
//  roomscan
//

import SwiftUI

struct ScanCompletionView: View {
    let scan: RoomScanSummary
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon Header
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text(scan.name)
                        .font(.title.bold())
                        .accessibilityIdentifier("scanDetails.name")

                    Text(String(localized: "scandetails.status.format \(scan.syncStatus.localizedTitle)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(statusColor(scan.syncStatus))
                        .accessibilityIdentifier("scanDetails.syncStatus")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "scandetails.label.created_date"))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .fontWeight(.medium)
                    }

                    Divider()

                    HStack {
                        Text(String(localized: "scandetails.label.notes_count"))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(scan.notes.count)")
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .background(Color(uiColor: UIColor.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 20)

                Spacer()

                Button {
                    onDone()
                    dismiss()
                } label: {
                    Text(String(localized: "scandetails.action.done"))
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .accessibilityIdentifier("scanDetails.doneButton")
            }
            .navigationTitle(String(localized: "scandetails.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func statusColor(_ status: RoomScanSyncStatus) -> Color {
        switch status {
        case .synced:
            return .green
        case .uploading, .pending:
            return .orange
        case .failed:
            return .red
        }
    }
}
