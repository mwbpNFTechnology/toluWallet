//
//  QRScannerView.swift
//  toluWallet
//
//  Full-screen QR scanner in the tolu style: the camera, a lime frame, and a
//  line saying what to point at.
//

import SwiftUI

struct QRScannerView: View {
    let title: String
    let hint: String
    /// Return `nil` to accept the code, or a message to show and keep scanning.
    let onCode: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var cameraUnavailable = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(
                onCode: { code in
                    if let problem = onCode(code) {
                        message = problem
                        return false
                    }
                    dismiss()
                    return true
                },
                onUnavailable: { cameraUnavailable = true }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.5), in: Circle())
                        .buttonStyle(.plain)
                    Spacer()
                    MonoLabel("◉ \(title)", size: 10, color: Tolu.Palette.lime, tracking: 2)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, Tolu.Spacing.screen)
                .padding(.top, 12)

                Spacer()

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Tolu.Palette.lime, lineWidth: 3)
                    .frame(width: 260, height: 260)
                    .accessibilityHidden(true)

                Spacer()

                Text(statusText)
                    .font(.system(size: 14))
                    .foregroundStyle(statusIsProblem ? Tolu.Palette.coral : .white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var statusIsProblem: Bool { cameraUnavailable || message != nil }

    private var statusText: String {
        if cameraUnavailable {
            return "The camera isn't available. Allow camera access for toluWallet in Settings."
        }
        return message ?? hint
    }
}

#Preview {
    QRScannerView(title: "wallet address", hint: "point at the QR on the device") { _ in nil }
}
