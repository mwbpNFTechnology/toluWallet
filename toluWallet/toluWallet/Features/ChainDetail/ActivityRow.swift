//
//  ActivityRow.swift
//  toluWallet
//
//  One line of history. Opens the transaction on the chain's explorer.
//

import SwiftUI

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        if let url = item.url {
            Link(destination: url) { content }
                .buttonStyle(PressableCardStyle())
                .accessibilityHint("Opens the transaction on the explorer")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(tint.opacity(0.08))
                    .overlay(Circle().stroke(tint.opacity(0.55), lineWidth: 1))
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Tolu.Palette.text)
                        .lineLimit(1)
                    if item.failed {
                        MonoLabel("failed", size: 8, color: Tolu.Palette.coral, tracking: 1)
                    }
                }
                MonoLabel(counterpartyText, size: 8.5, tracking: 0.9)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                if let amountText = item.amountText {
                    Text(sign + amountText)
                        .font(.toluMono(12.5))
                        .foregroundStyle(item.failed ? Tolu.Palette.dim : amountColor)
                        .strikethrough(item.failed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if let date = item.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.toluMono(8.5))
                        .textCase(.uppercase)
                        .foregroundStyle(Tolu.Palette.dim)
                } else {
                    MonoLabel("pending", size: 8.5, color: Tolu.Palette.amber, tracking: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .toluCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        if item.failed { return Tolu.Palette.coral }
        switch item.direction {
        case .incoming: return Tolu.Palette.lime
        case .outgoing: return Tolu.Palette.sky
        case .neutral: return Tolu.Palette.mute
        }
    }

    private var symbol: String {
        switch item.direction {
        case .incoming: return "arrow.down"
        case .outgoing: return "arrow.up"
        case .neutral: return "arrow.left.arrow.right"
        }
    }

    private var sign: String {
        switch item.direction {
        case .incoming: return "+"
        case .outgoing: return "−"
        case .neutral: return ""
        }
    }

    private var amountColor: Color {
        item.direction == .incoming ? Tolu.Palette.lime : Tolu.Palette.text
    }

    private var counterpartyText: String {
        guard let counterparty = item.counterparty else { return EthereumAddress.short(item.hash) }
        let prefix = item.direction == .incoming ? "from" : "to"
        return "\(prefix) \(EthereumAddress.short(counterparty))"
    }
}

#Preview {
    VStack(spacing: 8) {
        ActivityRow(item: ActivityItem(
            id: "1", hash: "0xabc", date: .now.addingTimeInterval(-3600), direction: .incoming,
            title: "Received", amountText: "25 USDC",
            counterparty: "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf", failed: false, url: nil
        ))
        ActivityRow(item: ActivityItem(
            id: "2", hash: "0xdef", date: .now.addingTimeInterval(-86_400), direction: .outgoing,
            title: "Sent", amountText: "0.0100 ETH",
            counterparty: "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf", failed: true, url: nil
        ))
    }
    .padding()
    .background(Tolu.Palette.ink)
}
