//
//  SeedWordCell.swift
//  toluWallet
//
//  One word of a seed phrase with its position, or — while the words must not
//  be seen — the position alone.
//

import SwiftUI

struct SeedWordCell: View {
    /// One-based position in the phrase.
    let number: Int
    /// `nil` hides the word.
    let word: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(number, format: .number)
                .toluMono(10)
                .foregroundStyle(Tolu.Palette.dim)
                .frame(width: 18, alignment: .trailing)
            Text(word ?? "••••••")
                .toluFont(16, weight: .medium)
                .foregroundStyle(word == nil ? Tolu.Palette.dim : Tolu.Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .toluCard(radius: 12)
        // Two columns of words: past this size the longest words would be
        // cut short, and a seed word must never be shown truncated.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.map { "Word \(number): \($0)" } ?? "Word \(number), hidden")
    }
}

#Preview {
    VStack(spacing: 8) {
        SeedWordCell(number: 1, word: "abandon")
        SeedWordCell(number: 12, word: nil)
    }
    .padding()
    .background(Tolu.Palette.ink)
}
