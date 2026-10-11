//
//  ToluHeading.swift
//  toluWallet
//
//  Lowercase display heading with a colored accent period,
//  matching the tolu design language (e.g. "your wallets.").
//

import SwiftUI

struct ToluHeading: View {
    let text: String
    var size: CGFloat = 34
    var accent: Color = Tolu.Palette.lime

    var body: some View {
        Text("\(Text(text).foregroundStyle(Tolu.Palette.text))\(Text(".").foregroundStyle(accent))")
            .font(.toluTitle(size))
            .tracking(-0.5)
            .lineSpacing(2)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ToluHeading(text: "your wallets")
        ToluHeading(text: "send it", accent: Tolu.Palette.violet)
    }
    .padding()
    .background(Tolu.Palette.ink)
}
