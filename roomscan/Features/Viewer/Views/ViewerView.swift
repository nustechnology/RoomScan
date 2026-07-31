//
//  ViewerView.swift
//  roomscan
//

import SwiftUI

struct ViewerView: View {
    @State private var viewModel: ViewerViewModel
    let shareService: any ShareService
    @State private var renameTitle = ""
    @State private var isRenamePresented = false
    @State private var isSharePresented = false
    var onBack: (() -> Void)?
    var onScanRenamed: ((String) -> Void)?

    init(
        input: ViewerInput,
        notesService: any NotesService,
        modelLoadingService: any ModelLoadingService,
        accessPolicy: DetailAccessPolicy = .editable,
        shareService: any ShareService,
        onBack: (() -> Void)? = nil,
        onScanRenamed: ((String) -> Void)? = nil
    ) {
        _viewModel = State(
            initialValue: ViewerViewModel(
                input: input,
                notesService: notesService,
                modelLoadingService: modelLoadingService,
                accessPolicy: accessPolicy
            )
        )
        self.shareService = shareService
        self.onBack = onBack
        self.onScanRenamed = onScanRenamed
    }

    init(
        input: ViewerInput,
        notesService: any NotesService,
        accessPolicy: DetailAccessPolicy = .editable,
        shareService: any ShareService,
        onBack: (() -> Void)? = nil,
        onScanRenamed: ((String) -> Void)? = nil
    ) {
        self.init(
            input: input,
            notesService: notesService,
            modelLoadingService: DefaultModelLoadingService(),
            accessPolicy: accessPolicy,
            shareService: shareService,
            onBack: onBack,
            onScanRenamed: onScanRenamed
        )
    }

    init(
        viewModel: ViewerViewModel,
        shareService: any ShareService,
        onBack: (() -> Void)? = nil,
        onScanRenamed: ((String) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.shareService = shareService
        self.onBack = onBack
        self.onScanRenamed = onScanRenamed
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.medium)

            ViewerModeSwitcher(
                selectedMode: viewModel.viewMode,
                isEnabled: viewModel.isModelReady,
                onSelect: { viewModel.setViewMode($0) }
            )
            .padding(.horizontal, AppSpacing.extraLarge)
            .padding(.bottom, AppSpacing.medium)

            canvasSection
                .padding(.horizontal, viewModel.isFullscreen ? 0 : AppSpacing.extraLarge)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isFullscreen)

            if !viewModel.isFullscreen && viewModel.isModelReady {
                ZStack(alignment: .top) {
                    NotesListSection(
                        notes: viewModel.notes,
                        selectedNoteID: viewModel.selectedNoteID,
                        isAddEnabled: viewModel.isModelReady && viewModel.allowsOwnerActions,
                        showsOwnerActions: viewModel.allowsOwnerActions,
                        onAddNote: { viewModel.beginAddNote() },
                        onSelectNote: { viewModel.selectNote(id: $0.id) },
                        onEditNote: { viewModel.openEditor(for: $0) },
                        onMoveNote: { viewModel.beginMoveNote($0) },
                        onDeleteNote: { viewModel.requestDelete($0) }
                    )

                    if viewModel.isPlacementActive {
                        PinPlacementBanner(
                            mode: viewModel.movingNote == nil ? .add : .move,
                            hasDraftPosition: viewModel.placementDraftPosition != nil,
                            onCancel: { viewModel.cancelPlacement() },
                            onDone: { viewModel.confirmPlacement() }
                        )
                        .padding(AppSpacing.medium)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, AppSpacing.extraLarge)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.extraLarge)
                .frame(maxHeight: 300)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.background)
        .overlay { alertHosts }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFullscreen)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .fullScreenCover(item: Binding(
            get: { viewModel.editorMode },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissEditor()
                }
            }
        )) { editorMode in
            NoteEditorSheet(
                mode: editorMode,
                onSave: { title, description, color in
                    await viewModel.saveEditor(
                        title: title,
                        description: description,
                        color: color
                    )
                },
                onCancel: { viewModel.dismissEditor() }
            )
        }
        .alert(
            String(localized: "viewer.scan.rename.title"),
            isPresented: $isRenamePresented
        ) {
            TextField(String(localized: "viewer.scan.rename.placeholder"), text: $renameTitle)
            Button(String(localized: "viewer.scan.rename.cancel"), role: .cancel) {}
            Button(String(localized: "viewer.scan.rename.save")) {
                if viewModel.renameScan(to: renameTitle) {
                    onScanRenamed?(viewModel.scanTitle)
                }
            }
        }
        .fullScreenCover(isPresented: $isSharePresented) {
            ShareView(
                input: .scan(
                    projectID: viewModel.input.projectID,
                    projectName: viewModel.input.projectName,
                    scanID: viewModel.input.scanID,
                    scanName: viewModel.scanTitle
                ),
                service: shareService
            )
        }
        .accessibilityIdentifier("viewer.screen")
    }

    private var alertHosts: some View {
        ZStack {
            Color.clear
                .alert(
                    String(localized: "viewer.note.delete.title"),
                    isPresented: Binding(
                        get: { viewModel.showsDeleteConfirmation },
                        set: { if !$0 { viewModel.cancelDelete() } }
                    )
                ) {
                    Button(String(localized: "viewer.note.delete.cancel"), role: .cancel) {
                        viewModel.cancelDelete()
                    }
                    Button(String(localized: "viewer.note.delete.confirm"), role: .destructive) {
                        if let note = viewModel.notePendingDeletion {
                            Task {
                                await viewModel.confirmDelete(note)
                            }
                        }
                    }
                } message: {
                    Text("viewer.note.delete.message")
                }

            Color.clear
                .alert(
                    String(localized: "viewer.note.operationError.title"),
                    isPresented: Binding(
                        get: { viewModel.showsOperationError },
                        set: { if !$0 { viewModel.dismissOperationError() } }
                    )
                ) {
                    Button(String(localized: "viewer.note.operationError.dismiss"), role: .cancel) {
                        viewModel.dismissOperationError()
                    }
                } message: {
                    if let message = viewModel.operationErrorMessage {
                        Text(message)
                    }
                }
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        ViewerHeader(
            title: viewModel.scanTitle,
            areNotesVisible: viewModel.areNotesVisible,
            onBack: { onBack?() },
            onRename: {
                guard viewModel.allowsOwnerActions else { return }
                renameTitle = viewModel.scanTitle
                isRenamePresented = true
            },
            onToggleNotes: { viewModel.toggleNotesVisibility() },
            onShare: {
                guard viewModel.allowsOwnerActions else { return }
                isSharePresented = true
            },
            showsOwnerActions: viewModel.allowsOwnerActions
        )
    }

    @ViewBuilder
    private var canvasSection: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                .fill(Color(red: 0.90, green: 0.94, blue: 0.98))

            switch viewModel.loadState {
            case .idle, .loading:
                ViewerCanvasLoadingState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("viewer.loading")

            case .failed:
                ViewerCanvasErrorState(onRetry: { viewModel.retryLoad() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("viewer.loadError")

            case .loaded(let source):
                RoomModelCanvas(
                    modelSource: source,
                    notes: viewModel.visibleNotes,
                    selectedNoteID: viewModel.selectedNoteID,
                    viewMode: viewModel.viewMode,
                    isPlacementMode: viewModel.isPlacementActive,
                    movingNoteID: viewModel.draggableNoteID,
                    movePreviewPosition: viewModel.placementDraftPosition,
                    cameraCommand: viewModel.cameraCommand,
                    onCameraCommandConsumed: { viewModel.consumeCameraCommand() },
                    onPinTapped: { viewModel.handlePinTap(noteID: $0) },
                    onSurfaceTapped: { viewModel.handleCanvasTap(position: $0) },
                    onMoveDraftChanged: { viewModel.updateMoveDraft(position: $0) },
                    onModelLoadFailed: { viewModel.reportModelLoadFailed() }
                )
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
                .accessibilityIdentifier("viewer.canvas")
            }

            if case .loaded = viewModel.loadState {
                ViewControlToolbar(
                    isFullscreen: viewModel.isFullscreen,
                    isEnabled: viewModel.isModelReady,
                    onToggleFullscreen: { viewModel.toggleFullscreen() },
                    onZoomIn: { viewModel.zoomIn() },
                    onZoomOut: { viewModel.zoomOut() },
                    onReset: { viewModel.resetCamera() }
                )
                .padding(AppSpacing.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        .overlay(alignment: .bottom) {
            if viewModel.isFullscreen && viewModel.isPlacementActive {
                PinPlacementBanner(
                    mode: viewModel.movingNote == nil ? .add : .move,
                    hasDraftPosition: viewModel.placementDraftPosition != nil,
                    onCancel: { viewModel.cancelPlacement() },
                    onDone: { viewModel.confirmPlacement() }
                )
                .padding(AppSpacing.medium)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

private struct ViewerModeSwitcher: View {
    let selectedMode: ViewerMode
    let isEnabled: Bool
    let onSelect: (ViewerMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ViewerMode.allCases) { mode in
                let isSelected = selectedMode == mode
                Button {
                    onSelect(mode)
                } label: {
                    Text(mode.localizedTitle)
                        .appTypography(AppTypography.bodyMediumStrong)
                        .foregroundStyle(AppColors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(AppColors.background)
                                    .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityIdentifier("viewer.mode.switcher")
    }
}

private struct ViewerHeader: View {
    let title: String
    let areNotesVisible: Bool
    let onBack: () -> Void
    let onRename: () -> Void
    let onToggleNotes: () -> Void
    let onShare: () -> Void
    let showsOwnerActions: Bool

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            circleButton(
                systemImage: "chevron.left",
                accessibilityLabel: String(localized: "common.back"),
                accessibilityIdentifier: "viewer.back",
                action: onBack
            )

            Text(title)
                .appTypography(AppTypography.headingLarge)
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)

            Menu {
                if showsOwnerActions {
                    Button(action: onRename) {
                        Label(String(localized: "viewer.menu.rename"), systemImage: "pencil")
                    }
                }

                Button(action: onToggleNotes) {
                    if areNotesVisible {
                        Label(String(localized: "viewer.menu.hideNotes"), systemImage: "eye.slash")
                    } else {
                        Label(String(localized: "viewer.menu.showNotes"), systemImage: "eye")
                    }
                }

                if showsOwnerActions {
                    Button(action: onShare) {
                        Label(String(localized: "viewer.menu.shareScan"), systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .accessibilityLabel(String(localized: "viewer.header.more"))
            .accessibilityIdentifier("viewer.more")
        }
    }

    private func circleButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ViewerCanvasLoadingState: View {
    var body: some View {
        VStack(spacing: AppSpacing.large) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColors.brandBlueBottom)
                .scaleEffect(1.3)

            VStack(spacing: AppSpacing.small) {
                Text("viewer.loading")
                    .appTypography(AppTypography.bodyMediumStrong)
                    .foregroundStyle(AppColors.primaryText)

                Text("viewer.loading.detail")
                    .appTypography(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .padding(AppSpacing.extraLarge)
    }
}

private struct ViewerCanvasErrorState: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppColors.error)

            VStack(spacing: AppSpacing.small) {
                Text("viewer.load.error")
                    .appTypography(AppTypography.bodyLargeStrong)
                    .foregroundStyle(AppColors.error)

                Text("viewer.load.error.detail")
                    .appTypography(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.secondaryText)
            }

            PrimaryActionButton(
                title: String(localized: "viewer.load.retry"),
                systemImageName: "arrow.clockwise",
                color: AppColors.background,
                action: onRetry,
                foregroundColor: AppColors.primaryText,
                borderColor: Color.primary.opacity(0.12),
                accessibilityIdentifier: "viewer.load.retry"
            )
            .frame(maxWidth: 330)
        }
        .multilineTextAlignment(.center)
        .padding(AppSpacing.extraLarge)
    }
}

private struct PinPlacementBanner: View {
    enum Mode {
        case add
        case move
    }

    let mode: Mode
    let hasDraftPosition: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: "mappin.and.ellipse")
                .accessibilityHidden(true)

            Text(message)
                .appTypography(AppTypography.bodySmallStrong)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsDoneButton {
                Button(String(localized: "viewer.share.done"), action: onDone)
                    .appTypography(AppTypography.bodySmallStrong)
                    .accessibilityIdentifier("viewer.placement.done")
            }

            Button(String(localized: "viewer.placement.cancel"), action: onCancel)
                .appTypography(AppTypography.bodySmallStrong)
                .accessibilityIdentifier("viewer.placement.cancel")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .background(AppColors.primaryAction.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .accessibilityIdentifier("viewer.placement.banner")
    }

    private var message: String {
        switch mode {
        case .add:
            if hasDraftPosition {
                return String(localized: "viewer.placement.drag.banner")
            }
            return String(localized: "viewer.placement.banner")
        case .move:
            return String(localized: "viewer.placement.drag.banner")
        }
    }

    private var showsDoneButton: Bool {
        switch mode {
        case .add:
            return hasDraftPosition
        case .move:
            return true
        }
    }
}

#Preview {
    ViewerView(
        input: ViewerInput(scanID: "preview-scan", scanName: "Living Room"),
        notesService: MockNotesService(),
        shareService: MockShareService(simulatedDelayNanoseconds: 0),
        onBack: {}
    )
}
