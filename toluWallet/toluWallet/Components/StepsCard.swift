//
//  StepsCard.swift
//  toluWallet
//
//  A bordered checklist of `StepRow`s.
//

import SwiftUI

struct StepsCard: View {

    struct Item: Identifiable {
        let id: Int
        let state: StepState
        let title: String
        let hint: String
    }

    let steps: [Item]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(steps) { step in
                StepRow(state: step.state, title: step.title, hint: step.hint, first: step.id == steps.first?.id)
            }
        }
        .toluCard()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    StepsCard(steps: [
        .init(id: 0, state: .done, title: "Create the key", hint: "the tag generates secp256k1"),
        .init(id: 1, state: .active, title: "Verify", hint: "tap again to read the address back")
    ])
    .padding()
    .background(Tolu.Palette.ink)
}
