//
//  RoomCaptureViewRepresentable.swift
//  roomscan
//

import SwiftUI
#if canImport(RoomPlan)
import RoomPlan
#endif

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let captureService: RoomCaptureService

    func makeUIView(context: Context) -> UIView {
        ScanTelemetry.shared.recordRoomCaptureViewCreated()
        #if canImport(RoomPlan)
        if #available(iOS 16.0, *), RoomCaptureSession.isSupported,
           let realService = captureService as? RoomPlanCaptureService {
            let captureView = RoomCaptureView(frame: .zero)
            realService.attachCaptureSession(captureView.captureSession)
            return captureView
        }
        #endif
        return makeMockView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func makeMockView() -> UIView {
        let view = UIView()
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1.0).cgColor,
            UIColor(red: 0.03, green: 0.05, blue: 0.08, alpha: 1.0).cgColor
        ]
        gradient.locations = [0.0, 1.0]
        gradient.frame = UIScreen.main.bounds
        view.layer.insertSublayer(gradient, at: 0)
        return view
    }
}
