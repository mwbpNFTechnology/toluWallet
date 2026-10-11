//
//  SectionHeader.swift
//  toluWallet
//
//  A mono section title with a hairline rule and an optional trailing note.
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 9) {
            MonoLabel(title, size: 9, color: Tolu.Palette.dim, tracking: 1.5)
            Rectangle().fill(Tolu.Palette.line).frame(height: 1)
            if let trailing {
                MonoLabel(trailing, size: 9, color: Tolu.Palette.dim, tracking: 1.2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    SectionHeader(title: "balances", trailing: "by chain id")
        .padding()
        .background(Tolu.Palette.ink)
}
