//
//  NftCollectionRow.swift
//  toluWallet
//
//  One NFT collection on a chain screen, with the ids the wallet holds.
//

import SwiftUI

struct NftCollectionRow: View {
    let collection: NftCollection

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Tolu.Palette.ink3)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Tolu.Palette.line2, lineWidth: 1))
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(Tolu.Palette.mute)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .tracking(-0.25)
                    .foregroundStyle(Tolu.Palette.text)
                    .lineLimit(1)
                MonoLabel(idsText, size: 8.5, tracking: 1)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(collection.count)")
                    .font(.toluMono(14))
                    .foregroundStyle(Tolu.Palette.text)
                MonoLabel(collection.standard, size: 8.5, tracking: 0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .toluCard()
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Copy contract address", systemImage: "doc.on.doc") {
                Clipboard.copy(collection.address)
            }
        }
    }

    /// "#12, #40 +3" — long ids are shortened.
    private var idsText: String {
        let shown = collection.tokenIds.prefix(3).map { id in
            id.count > 8 ? "#\(id.prefix(4))…\(id.suffix(2))" : "#\(id)"
        }
        guard !shown.isEmpty else { return EthereumAddress.short(collection.address) }
        let extra = collection.count - shown.count
        return shown.joined(separator: ", ") + (extra > 0 ? " +\(extra)" : "")
    }
}

#Preview {
    NftCollectionRow(collection: NftCollection(
        chain: ChainRegistry.all[0], address: "0x0000000000696760E15f265e828DB644A0c242EB",
        name: "Wei Name Service", standard: "ERC-721", count: 5, tokenIds: ["12", "40"]
    ))
    .padding()
    .background(Tolu.Palette.ink)
}
