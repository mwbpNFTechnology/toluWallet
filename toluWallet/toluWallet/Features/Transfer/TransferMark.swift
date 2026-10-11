//
//  TransferMark.swift
//  toluWallet
//
//  The ring at the top of the signing screen: a turning arc while something is
//  in flight, a full ring once the transfer has settled.
//

import SwiftUI

struct TransferMark: View {
    let systemImage: String
    let accent: Color
    let isSpinning: Bool
    let isComplete: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle().stroke(Tolu.Palette.line2, lineWidth: 3)
            Circle()
                .trim(from: 0, to: isComplete ? 1 : 0.22)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(isSpinning && turn ? 270 : -90))
                .animation(
                    isSpinning && !reduceMotion
                        ? .linear(duration: 1.4).repeatForever(autoreverses: false)
                        : .default,
                    value: turn
                )
            Circle()
                .fill(accent.opacity(0.08))
                .overlay(Circle().stroke(accent, lineWidth: 1))
                .frame(width: 72, height: 72)
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(accent)
        }
        .frame(width: 118, height: 118)
        .accessibilityHidden(true)
        .onChange(of: isSpinning, initial: true) { _, spinning in
            turn = spinning
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        TransferMark(systemImage: "wave.3.forward", accent: Tolu.Palette.amber, isSpinning: true, isComplete: false)
        TransferMark(systemImage: "checkmark", accent: Tolu.Palette.lime, isSpinning: false, isComplete: true)
    }
    .padding()
    .background(Tolu.Palette.ink)
}
