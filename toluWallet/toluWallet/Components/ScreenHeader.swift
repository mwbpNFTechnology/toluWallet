//
//  ScreenHeader.swift
//  toluWallet
//
//  Custom top bar for pushed screens: a back chevron on the left, a centered
//  mono title, and an optional trailing control. The system navigation bar is
//  hidden so this matches the tolu design.
//

import SwiftUI

struct ScreenHeader<Trailing: View>: View {
    let title: String
    var accent: Color = Tolu.Palette.lime
    var backSystemImage: String = "chevron.left"
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            MonoLabel(title, size: 11, color: Tolu.Palette.text, tracking: 2)

            HStack {
                Button("Back", systemImage: backSystemImage, action: onBack)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, Tolu.Spacing.screen)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tolu.Palette.line)
                .frame(height: 1)
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, accent: Color = Tolu.Palette.lime,
         backSystemImage: String = "chevron.left", onBack: @escaping () -> Void) {
        self.init(title: title, accent: accent, backSystemImage: backSystemImage,
                  onBack: onBack, trailing: { EmptyView() })
    }
}

#Preview {
    ScreenHeader(title: "wallet") {}
        .background(Tolu.Palette.ink)
}
