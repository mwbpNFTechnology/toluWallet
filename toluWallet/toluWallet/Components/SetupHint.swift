//
//  SetupHint.swift
//  toluWallet
//
//  The small mono line under a setup field.
//

import SwiftUI

struct SetupHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.toluMono(9))
            .foregroundStyle(Tolu.Palette.dim)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
