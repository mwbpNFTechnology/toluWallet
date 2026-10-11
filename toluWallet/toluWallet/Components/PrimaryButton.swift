//
//  PrimaryButton.swift
//  toluWallet
//
//  Full-width filled action button used for the main call to action on a
//  screen. While `isLoading` it shows a spinner in place of the icon.
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var accent: Color = Tolu.Palette.lime
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        accent: Color = Tolu.Palette.lime,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView().tint(Tolu.Palette.ink)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Tolu.Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!isEnabled)
    }
}

#Preview {
    VStack(spacing: 12) {
        PrimaryButton("Tap tag to sign", systemImage: "wave.3.forward") {}
        PrimaryButton("Hold the tag…", isEnabled: false, isLoading: true) {}
    }
    .padding()
    .background(Tolu.Palette.ink)
}
