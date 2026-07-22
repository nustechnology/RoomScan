//
//  SplashScreenView.swift
//  roomscan
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isVisible = false
    @ScaledMetric(relativeTo: .title) private var fontSize: CGFloat = 34

    private enum Metrics {
        static let logoSize: CGFloat = 240
        static let textOffset: CGFloat = -logoSize * 0.35
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppColors.brandBlueTop,
                    AppColors.brandBlueBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Metrics.textOffset) {
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.logoSize, height: Metrics.logoSize)
                    .shadow(
                        color: AppShadows.logoColor,
                        radius: 14,
                        y: 7
                    )

                Text("auth.title")
                    .font(.system(size: fontSize, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .offset(y: isVisible ? 0 : 6)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = true
            }
        }
        .accessibilityIdentifier("app.loading")
    }
}

#Preview {
    SplashScreenView()
}
