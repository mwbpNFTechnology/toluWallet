//
//  Pill.swift
//  toluWallet
//
//  A small status capsule with a colored dot (tolu's vault pill).
//

import SwiftUI

struct Pill: View {
    let text: String
    var color: Color = Tolu.Palette.dim
    var showsDot: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            MonoLabel(text, size: 8.5, color: color, tracking: 1.1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 1))
    }
}

#Preview {
    HStack {
        Pill(text: "testnet", color: Tolu.Palette.amber)
        Pill(text: "chain 8453", showsDot: false)
    }
    .padding()
    .background(Tolu.Palette.ink)
}
