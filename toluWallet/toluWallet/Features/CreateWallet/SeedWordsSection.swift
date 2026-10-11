//
//  SeedWordsSection.swift
//  toluWallet
//
//  The seed phrase, shown once so it can be written down. The words are
//  hidden whenever this screen could be captured: while it is being recorded
//  or mirrored, and while the app is not in front (which is when the system
//  takes its app-switcher picture).
//

import SwiftUI

struct SeedWordsSection: View {
    let model: CreateWalletViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured

    private let accent = Tolu.Palette.lime

    private var wordsAreVisible: Bool { scenePhase == .active && !isSceneCaptured }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ToluHeading(text: "write these\n\(model.words.count) words down", accent: accent)
                Text("In this order, on paper. They are the only backup of this wallet — and anyone who has them has the wallet. They were made from a random number generated inside the tag's secure element, mixed with this phone's own.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tolu.Palette.mute)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = model.wordsNotice {
                Text(notice)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tolu.Palette.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSceneCaptured {
                NoticeCard(
                    systemImage: "record.circle",
                    text: "The screen is being recorded or mirrored, so the words are hidden. Stop it to see them.",
                    color: Tolu.Palette.coral
                )
            }

            HStack(alignment: .top, spacing: 10) {
                column(model.words.indices.prefix(leftColumnCount))
                column(model.words.indices.dropFirst(leftColumnCount))
            }

            NoticeCard(
                systemImage: "eye.slash",
                text: "No screenshot, no photo, no notes app — and nobody looking over your shoulder. The words are shown only now: once the key is on the tag, this phone forgets them."
            )
            NoticeCard(
                systemImage: "clock",
                text: "Leave the app for more than a minute, or stay longer than ten, and these words are erased: you would start again with new ones.",
                color: Tolu.Palette.violet
            )
        }
    }

    /// Words run down the left column, then down the right.
    private var leftColumnCount: Int { (model.words.count + 1) / 2 }

    private func column(_ indices: some Collection<Int>) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(indices), id: \.self) { index in
                SeedWordCell(number: index + 1, word: wordsAreVisible ? model.words[index] : nil)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ScrollView {
        SeedWordsSection(model: CreateWalletViewModel(store: WalletStore()))
            .padding()
    }
    .background(Tolu.Palette.ink)
}
