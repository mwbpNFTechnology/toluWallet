//
//  TapTargetStyle.swift
//  toluWallet
//
//  A plain button style for small glyph and text buttons: the tappable area
//  reaches past the label to Apple's 44 × 44 pt minimum, while the layout
//  around it stays exactly as drawn.
//

import SwiftUI

struct TapTargetStyle: ButtonStyle {
    /// Enough on every side that even a 10 pt label gets a 44 pt target.
    private static let outset: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(Self.outset)
            .contentShape(.rect)
            .padding(-Self.outset)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
