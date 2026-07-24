//
//  ToastModifier.swift
//  roomscan
//

import SwiftUI

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "exclamationmark.circle.fill")
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
                .fill(AppColors.error)
                .shadow(color: AppShadows.actionColor, radius: 8, y: 4)
        )
        .padding(.horizontal, AppSpacing.large)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var timerTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let message {
                ToastView(message: message)
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
        .onChange(of: message) { _, newValue in
            timerTask?.cancel()
            if newValue != nil {
                timerTask = Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if !Task.isCancelled {
                        await MainActor.run {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func dismiss() {
        message = nil
    }
}

extension View {
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
