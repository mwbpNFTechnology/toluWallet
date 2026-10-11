//
//  DetailRow.swift
//  toluWallet
//
//  A "LABEL ———— value" line for summary cards.
//

import SwiftUI

struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = Tolu.Palette.mute

    var body: some View {
        HStack(spacing: 8) {
            MonoLabel(label, size: 8.5, color: Tolu.Palette.dim, tracking: 1.2)
            Rectangle().fill(Tolu.Palette.line).frame(height: 1)
            Text(value)
                .font(.toluMono(11))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 9) {
        DetailRow(label: "to", value: "0x12345678…abcd", valueColor: Tolu.Palette.text)
        DetailRow(label: "network fee", value: "≤ 0.000021 ETH")
    }
    .padding()
    .background(Tolu.Palette.ink)
}
