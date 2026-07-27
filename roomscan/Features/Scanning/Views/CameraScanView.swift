//
//  CameraScanView.swift
//  roomscan
//

import SwiftUI

struct CameraScanView: View {
    @StateObject var viewModel: CameraScanViewModel
    @State private var showingInfoSheet = false
    let onFinish: (RoomScanDraft) -> Void
    let onCancel: () -> Void

    init(
        sourceProjectID: String? = nil,
        captureService: RoomCaptureService? = nil,
        onFinish: @escaping (RoomScanDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CameraScanViewModel(
            sourceProjectID: sourceProjectID,
            captureService: captureService
        ))
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // Camera Preview background
            RoomCaptureViewRepresentable(captureService: viewModel.captureService)
                .ignoresSafeArea()

            // Wireframe Grid Overlay (Visual decoration matching screenshot)
            ScanningGridOverlayView()
                .padding(.horizontal, 24)
                .padding(.vertical, 80)

            // UI Overlays
            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    Text(String(localized: "scanning.title"))
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        showingInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel(String(localized: "scanning.info.accessibility_label"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Guidance Toast
                HStack {
                    Spacer()
                    Text(String(localized: "scanning.toast.guidance"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(16)
                    Spacer()
                }
                .padding(.top, 16)

                Spacer()

                // Loading Overlay if processing finish
                if viewModel.isProcessingFinish {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text(String(localized: "scanning.processing_mesh"))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.bottom, 20)
                }

                // Bottom Control Bar
                HStack(spacing: 0) {
                    // Cancel Button
                    Button {
                        viewModel.handleCancelTapped()
                    } label: {
                        Text(String(localized: "scanning.action.cancel"))
                            .font(.body.weight(.semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(30)
                    }
                    .accessibilityIdentifier("scanning.cancelButton")

                    Spacer()

                    // Center Shutter/Record Button Graphic (Decorative)
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 68, height: 68)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.blue)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityHidden(true)

                    Spacer()

                    // Finish Button
                    Button {
                        print("[RoomScan STEP 1] Finish button tapped in CameraScanView")
                        Task {
                            if let draft = await viewModel.finishScan() {
                                print("[RoomScan STEP 5] finishScan completed, calling onFinish(draft)...")
                                onFinish(draft)
                            } else {
                                print("[RoomScan STEP 5-ERROR] finishScan returned nil!")
                            }
                        }
                    } label: {
                        Text(String(localized: "scanning.action.finish"))
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(viewModel.hasMinimalStructure ? Color.blue : Color.blue.opacity(0.4))
                            .cornerRadius(30)
                    }
                    .disabled(!viewModel.hasMinimalStructure || viewModel.isProcessingFinish)
                    .accessibilityIdentifier("scanning.finishButton")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
        }
        .onAppear {
            ScanTelemetry.shared.recordCameraViewInitialized()
            viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
        .confirmationDialog(
            String(localized: "scanning.cancel.title"),
            isPresented: $viewModel.showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "scanning.cancel.resume"), role: .cancel) {
                viewModel.resumeScanning()
            }
            Button(String(localized: "scanning.cancel.discard"), role: .destructive) {
                viewModel.discardAndExit()
                onCancel()
            }
        }
        .alert(
            String(localized: "scanning.alert.storage_full.title"),
            isPresented: Binding(
                get: { viewModel.isStorageFull },
                set: { _ in }
            )
        ) {
            Button(String(localized: "common.action.ok"), role: .cancel) {
                onCancel()
            }
        } message: {
            Text(viewModel.errorMessage ?? String(localized: "scanning.error.storage_full"))
        }
        .sheet(isPresented: $showingInfoSheet) {
            ScanningInfoSheet()
        }
    }
}

private struct ScanningInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "scanning.info.header"))
                    .font(.headline)

                VStack(alignment: .leading, spacing: 16) {
                    Label(String(localized: "scanning.info.tip1"), systemImage: "lightbulb")
                    Label(String(localized: "scanning.info.tip2"), systemImage: "sun.max")
                    Label(String(localized: "scanning.info.tip3"), systemImage: "viewfinder")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle(String(localized: "scanning.info.accessibility_label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.action.ok")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Scanning Grid Overlay Visual Element
struct ScanningGridOverlayView: View {
    var body: some View {
        GeometryReader { geo in
            let cols = 10
            let rows = 16
            Path { path in
                let cellW = geo.size.width / CGFloat(cols)
                let cellH = geo.size.height / CGFloat(rows)

                for i in 0...cols {
                    let x = CGFloat(i) * cellW
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }

                for j in 0...rows {
                    let y = CGFloat(j) * cellH
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.green.opacity(0.5), lineWidth: 1)
            .overlay(
                Rectangle()
                    .stroke(Color.green, lineWidth: 2)
            )
        }
    }
}
