//
//  AddressBar.swift
//  toluWallet
//
//  An address on one line with a copy button.
//

import SwiftUI

struct AddressBar: View {
    let address: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(address)
                .font(.toluMono(11.5))
                .foregroundStyle(Tolu.Palette.mute)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button(copied ? "Copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(address)
                copied = true
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(copied ? Tolu.Palette.lime : Tolu.Palette.mute)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .toluCard(radius: 10)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

#Preview {
    AddressBar(address: "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf")
        .padding()
        .background(Tolu.Palette.ink)
}
