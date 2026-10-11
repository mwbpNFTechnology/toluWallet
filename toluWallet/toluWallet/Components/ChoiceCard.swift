//
//  ChoiceCard.swift
//  toluWallet
//
//  One option in a pick-one list: a bordered card with a radio mark, a title
//  and a mono description.
//

import SwiftUI

struct ChoiceCard: View {
    let title: String
    let detail: String
    let isSelected: Bool
    var accent: Color = Tolu.Palette.lime
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? accent : Tolu.Palette.line2, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 11, height: 11)
                    }
                }
                .padding(.top, 1)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tolu.Palette.text)
                    Text(detail)
                        .font(.toluMono(9))
                        .foregroundStyle(Tolu.Palette.dim)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .toluCard(radius: Tolu.Radius.card, fill: Tolu.Palette.ink2,
                      stroke: isSelected ? accent.opacity(0.6) : Tolu.Palette.line)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 10) {
        ChoiceCard(title: "Made inside the tag", detail: "the tag generates the key and it never leaves.",
                   isSelected: true) {}
        ChoiceCard(title: "From a seed phrase", detail: "this phone makes 12 words for you to write down.",
                   isSelected: false) {}
    }
    .padding()
    .background(Tolu.Palette.ink)
}
