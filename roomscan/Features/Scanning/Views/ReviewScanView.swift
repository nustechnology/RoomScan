//
//  ReviewScanView.swift
//  roomscan
//

import SwiftUI

struct ReviewScanView: View {
    @StateObject var viewModel: ReviewScanViewModel
    @FocusState private var isScanNameFocused: Bool
    let onSaveSuccess: (RoomScanSummary) -> Void
    let onScanAgain: () -> Void
    let onDiscard: () -> Void

    init(
        draft: RoomScanDraft,
        preselectedProjectID: String? = nil,
        projectsService: ProjectsService,
        onSaveSuccess: @escaping (RoomScanSummary) -> Void,
        onScanAgain: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ReviewScanViewModel(
            draft: draft,
            preselectedProjectID: preselectedProjectID,
            projectsService: projectsService
        ))
        self.onSaveSuccess = onSaveSuccess
        self.onScanAgain = onScanAgain
        self.onDiscard = onDiscard
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // 3D Model Preview Component
                    Model3DPreviewView(
                        meshURL: viewModel.draft.meshFileURL
                    )

                    // Form Inputs
                    VStack(alignment: .leading, spacing: 20) {
                        // Scan Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "review.label.scan_name"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)

                            TextField(String(localized: "review.placeholder.scan_name"), text: $viewModel.scanName)
                                .font(.body)
                                .focused($isScanNameFocused)
                                .onChange(of: viewModel.scanName) { _, newValue in
                                    if newValue.count > 50 {
                                        viewModel.scanName = String(newValue.prefix(50))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            viewModel.scanNameError != nil ? Color.red : Color(uiColor: UIColor.systemGray4),
                                            lineWidth: 1.5
                                        )
                                )
                                .accessibilityIdentifier("review.scanNameField")

                            if let error = viewModel.scanNameError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .accessibilityIdentifier("review.scanNameError")
                            }
                        }

                        projectSelectSection
                    }

                    Spacer(minLength: 20)

                    if let error = viewModel.saveErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("review.saveError")
                    }

                    // Primary Action: Save Scan
                    Button {
                        Task {
                            if let saved = await viewModel.saveScan() {
                                onSaveSuccess(saved)
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(16)
                        } else {
                            Text(String(localized: "review.action.save"))
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(viewModel.isSaveEnabled ? Color.blue : Color.blue.opacity(0.4))
                                .cornerRadius(16)
                        }
                    }
                    .disabled(!viewModel.isSaveEnabled)
                    .accessibilityIdentifier("review.saveButton")

                    // Secondary Bottom Actions (Scan Again / Discard)
                    HStack(spacing: 16) {
                        Button {
                            viewModel.cleanupDraftCache()
                            onScanAgain()
                        } label: {
                            Text(String(localized: "review.action.scan_again"))
                                .font(.body.weight(.semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(uiColor: UIColor.systemGray4), lineWidth: 1)
                                )
                        }
                        .accessibilityIdentifier("review.scanAgainButton")

                        Button {
                            viewModel.showDiscardConfirmation = true
                        } label: {
                            Text(String(localized: "review.action.discard"))
                                .font(.body.weight(.semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(16)
                        }
                        .accessibilityIdentifier("review.discardButton")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .foregroundStyle(Color.black)
        .preferredColorScheme(.light)
        .navigationTitle(String(localized: "review.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ToolbarBackButton(
                    action: { viewModel.showDiscardConfirmation = true },
                    accessibilityIdentifier: "review.backButton"
                )
            }
        }
        .task {
            await viewModel.loadProjects()
        }
        .sheet(isPresented: $viewModel.showCreateProjectModal) {
            InlineCreateProjectSheet(
                onCreate: { name in
                    await viewModel.createProject(name: name)
                },
                onCancel: {
                    viewModel.cancelCreateProjectModal()
                }
            )
        }
        .alert(
            String(localized: "review.discard.title"),
            isPresented: $viewModel.showDiscardConfirmation
        ) {
            Button(String(localized: "review.discard.cancel"), role: .cancel) {}
            Button(String(localized: "review.discard.confirm"), role: .destructive) {
                viewModel.cleanupDraftCache()
                onDiscard()
            }
        } message: {
            Text(String(localized: "review.discard.message"))
        }
    }

    private var projectSelectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "review.label.select_project"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(viewModel.projectSelectError == nil ? .secondary : .red)

            ZStack {
                projectDropdownFieldLabel
                    .accessibilityHidden(true)

                Menu {
                    Button {
                        viewModel.openCreateProjectModal()
                    } label: {
                        Label(String(localized: "review.action.create_project"), systemImage: "plus")
                    }

                    Divider()

                    ForEach(viewModel.projects) { project in
                        Button {
                            viewModel.selectedProjectID = project.id
                        } label: {
                            HStack {
                                Text(project.name)
                                if viewModel.selectedProjectID == project.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityIdentifier("review.projectOption.\(project.id)")
                    }
                } label: {
                    MenuTouchDownDetector(onTouchDown: dismissScanNameField)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(selectedProjectName)
                }
                .accessibilityIdentifier("review.selectProjectDropdown")
            }

            if let error = viewModel.projectSelectError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("review.selectProjectError")
            }
        }
    }

    private var projectDropdownFieldLabel: some View {
        HStack {
            Text(selectedProjectName)
                .font(.body)
                .foregroundColor(viewModel.selectedProjectID == nil ? .gray : .primary)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    viewModel.projectSelectError == nil
                    ? Color(uiColor: UIColor.systemGray4)
                    : Color.red,
                    lineWidth: 1.5
                )
        )
    }

    private var selectedProjectName: String {
        if let id = viewModel.selectedProjectID,
           let project = viewModel.projects.first(where: { $0.id == id }) {
            return project.name
        }
        return String(localized: "review.placeholder.select_project")
    }

    private func dismissScanNameField() {
        isScanNameFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// `Menu` swallows SwiftUI tap gestures, so detect press on the underlying UIControl instead.
private struct MenuTouchDownDetector: UIViewRepresentable {
    var onTouchDown: () -> Void

    func makeUIView(context: Context) -> MenuTouchDownView {
        let view = MenuTouchDownView()
        view.onTouchDown = onTouchDown
        return view
    }

    func updateUIView(_ uiView: MenuTouchDownView, context: Context) {
        uiView.onTouchDown = onTouchDown
    }
}

private final class MenuTouchDownView: UIView, UIGestureRecognizerDelegate {
    var onTouchDown: (() -> Void)?

    private lazy var pressRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handlePress)
        )
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachRecognizerToControl()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachRecognizerToControl()
    }

    private func attachRecognizerToControl() {
        pressRecognizer.view?.removeGestureRecognizer(pressRecognizer)
        var ancestor = superview
        while let view = ancestor {
            if view is UIControl {
                view.addGestureRecognizer(pressRecognizer)
                return
            }
            ancestor = view.superview
        }
        addGestureRecognizer(pressRecognizer)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onTouchDown?()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
