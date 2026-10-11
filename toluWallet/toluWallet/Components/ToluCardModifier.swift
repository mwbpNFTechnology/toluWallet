//
//  ToluCardModifier.swift
//  toluWallet
//
//  The raised, hairline-bordered surface every card in the tolu design sits on.
//

import SwiftUI

struct ToluCardModifier: ViewModifier {
    var radius: CGFloat
    var fill: Color
    var stroke: Color

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(stroke, lineWidth: 1))
    }
}

extension View {
    func toluCard(radius: CGFloat = 14,
                  fill: Color = Tolu.Palette.ink2,
                  stroke: Color = Tolu.Palette.line) -> some View {
        modifier(ToluCardModifier(radius: radius, fill: fill, stroke: stroke))
    }
}
