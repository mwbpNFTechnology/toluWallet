//
//  SeedQuizSection.swift
//  toluWallet
//
//  Confirms the seed phrase was written down: three of its words, each picked
//  out of three. A wrong answer goes back to the words.
//

import SwiftUI

struct SeedQuizSection: View {
    let model: CreateWalletViewModel

    private let accent = Tolu.Palette.lime

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let quiz = model.quiz {
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel("check \(quiz.question + 1) of \(SeedQuiz.questionCount)",
                              color: Tolu.Palette.violet, tracking: 1.8)
                    ToluHeading(text: "which one is\nword \(quiz.position + 1)", accent: accent)
                    Text("Read it from your paper, not from memory of the screen.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tolu.Palette.mute)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    ForEach(quiz.choices, id: \.self) { choice in
                        Button {
                            model.answerQuiz(choice)
                        } label: {
                            Text(choice)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Tolu.Palette.text)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .toluCard(radius: Tolu.Radius.control, fill: Tolu.Palette.ink3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .disabled(model.derivingKey)
                .opacity(model.derivingKey ? 0.5 : 1)
            }

            if model.derivingKey {
                HStack(spacing: 10) {
                    ProgressView().tint(accent)
                    Text("working out the key from your words…")
                        .font(.system(size: 13))
                        .foregroundStyle(Tolu.Palette.mute)
                }
            } else {
                Button("Show the words again", systemImage: "arrow.uturn.backward") {
                    model.backToWords()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(minHeight: 44)
            }
        }
    }
}

#Preview {
    ScrollView {
        SeedQuizSection(model: CreateWalletViewModel(store: WalletStore()))
            .padding()
    }
    .background(Tolu.Palette.ink)
}
