//
//  ToastModifier.swift
//  roomscan
//

import SwiftUI

enum ToastStyle: Equatable {
    case success
    case error

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .success:
            return AppColors.toastSuccess
        case .error:
            return AppColors.error
        }
    }
}

struct ToastView: View {
    let message: String
    let style: ToastStyle

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: style.iconName)
                .foregroundStyle(.white)

            Text(message)
                .appTypography(AppTypography.bodySmallStrong)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .fill(style.backgroundColor)
                .shadow(color: AppShadows.actionColor, radius: 8, y: 4)
        )
        .padding(.horizontal, AppSpacing.large)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @Binding var style: ToastStyle
    let presentationID: Int
    @State private var timerTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let message {
                ToastView(message: message, style: style)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                    .padding(.top, AppSpacing.medium)
                    .onTapGesture {
                        dismiss()
                    }
                    .accessibilityIdentifier("app.toast")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message != nil)
        .onChange(of: message) { _, _ in
            scheduleDismissal()
        }
        .onChange(of: presentationID) { _, _ in
            scheduleDismissal()
        }
    }

    private func scheduleDismissal() {
        timerTask?.cancel()
        guard message != nil else { return }
        timerTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }

    private func dismiss() {
        message = nil
    }
}

extension View {
    /// Change `presentationID` to restart the auto-dismiss timer when the same message is shown again.
    func toast(
        message: Binding<String?>,
        style: Binding<ToastStyle> = .constant(.error),
        presentationID: Int = 0
    ) -> some View {
        modifier(ToastModifier(message: message, style: style, presentationID: presentationID))
    }
}
