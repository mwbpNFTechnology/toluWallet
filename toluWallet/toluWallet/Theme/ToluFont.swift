//
//  ToluFont.swift
//  toluWallet
//
//  The tolu type scale for text. Sizes are the design's sizes at the default
//  text setting; they grow and shrink with the person's Dynamic Type choice,
//  each along the curve of the system text style closest to it.
//

import SwiftUI

struct ToluFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(near: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    private static func textStyle(near size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}

extension View {
    /// Body text at `size` points (SF Pro), scaled with Dynamic Type.
    func toluFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ToluFont(size: size, weight: weight, design: .default))
    }

    /// Tight sans heading (SF Pro stands in for Inter Tight), scaled with Dynamic Type.
    func toluTitle(_ size: CGFloat, weight: Font.Weight = .medium) -> some View {
        modifier(ToluFont(size: size, weight: weight, design: .default))
    }

    /// Monospaced label (SF Mono stands in for JetBrains Mono), scaled with Dynamic Type.
    func toluMono(_ size: CGFloat, weight: Font.Weight = .medium) -> some View {
        modifier(ToluFont(size: size, weight: weight, design: .monospaced))
    }
}
