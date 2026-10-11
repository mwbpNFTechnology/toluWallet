//
//  NoticeCard.swift
//  toluWallet
//
//  A tinted note with an icon — for the things worth reading before going on.
//

import SwiftUI

struct NoticeCard: View {
    let systemImage: String
    let text: String
    var color: Color = Tolu.Palette.amber

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Tolu.Palette.mute)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toluCard(radius: 12, fill: color.opacity(0.05), stroke: color.opacity(0.3))
    }
}

#Preview {
    NoticeCard(systemImage: "exclamationmark.triangle", text: "The key can't be exported or backed up.")
        .padding()
        .background(Tolu.Palette.ink)
}
