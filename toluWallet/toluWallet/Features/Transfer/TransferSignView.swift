//
//  TransferSignView.swift
//  toluWallet
//
//  Transfer, step two: the fee, the tap, and the wait for the network. After
//  tolu's vault send-sign screen.
//

import SwiftUI

struct TransferSignView: View {
    let controller: TransferController
    let onBack: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: controller.isComplete ? "transfer · done" : "transfer · 2 / 2",
                backSystemImage: controller.hasBroadcast ? "xmark" : "chevron.left",
                onBack: onBack
            )

            ScrollView {
                VStack(spacing: 14) {
                    TransferMark(systemImage: markSymbol, accent: accent,
                                 isSpinning: controller.running, isComplete: controller.isComplete)
                        .padding(.top, 12)
                    Pill(text: controller.statusText, color: accent)
                    headline
                    summaryCard
                    StepsCard(steps: TransferController.Step.allCases.map { step in
                        StepsCard.Item(id: step.id, state: controller.state(for: step),
                                       title: step.title, hint: controller.hint(for: step))
                    })
                    if let error = controller.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Tolu.Palette.coral)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = controller.explorerURL {
                        Link(destination: url) {
                            Label("View on explorer", systemImage: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Tolu.Palette.mute)
                        }
                    }
                }
                .padding(.horizontal, Tolu.Spacing.screen)
                .padding(.bottom, 16)
            }

            PrimaryButton(controller.actionTitle,
                          systemImage: actionSymbol,
                          isEnabled: controller.actionEnabled,
                          isLoading: controller.running) {
                if controller.isComplete {
                    onDone()
                } else {
                    controller.run()
                }
            }
            .padding(.horizontal, Tolu.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        // Read the nonce and fee straight away; signing waits for the tap.
        .task { controller.prepareIfNeeded() }
    }

    // MARK: - Pieces

    private var accent: Color {
        if controller.isComplete { return Tolu.Palette.lime }
        return controller.error == nil ? Tolu.Palette.amber : Tolu.Palette.coral
    }

    private var markSymbol: String {
        if controller.isComplete { return "checkmark" }
        switch controller.current {
        case .prepare: return "list.bullet.clipboard"
        case .sign: return "wave.3.forward"
        case .send: return "paperplane"
        case .confirm: return "hourglass"
        }
    }

    private var actionSymbol: String {
        if controller.isComplete { return "checkmark" }
        return controller.error == nil ? "wave.3.forward" : "arrow.clockwise"
    }

    private var title: String {
        if controller.isComplete { return "it left the wallet" }
        switch controller.current {
        case .prepare: return "getting it ready"
        case .sign: return "tap your tolu tag"
        case .send, .confirm: return "sending the transfer"
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text("\(title)\(Text(".").foregroundStyle(accent))")
                .font(.toluTitle(24))
                .tracking(-1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Tolu.Palette.text)
            Text(controller.isComplete
                 ? "The network confirmed it. The balance updates when you go back."
                 : "The tag signs this asset, this amount, this recipient on this network — and nothing else.")
                .font(.system(size: 13.5))
                .foregroundStyle(Tolu.Palette.mute)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 310)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Tolu.Palette.lime.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Tolu.Palette.lime, lineWidth: 1))
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tolu.Palette.lime)
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(controller.amountText) \(controller.draft.holding.symbol)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tolu.Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("out of \(controller.wallet.label)")
                        .font(.toluMono(9.5))
                        .foregroundStyle(Tolu.Palette.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Pill(text: controller.draft.holding.isNative ? "native" : "erc-20", color: Tolu.Palette.lime)
            }

            Rectangle().fill(Tolu.Palette.line).frame(height: 1)

            // The whole address, so it can be checked character by character.
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("to", size: 8.5, color: Tolu.Palette.dim, tracking: 1.2)
                Text(EthereumAddress.checksummed(controller.draft.recipient))
                    .font(.toluMono(11))
                    .foregroundStyle(Tolu.Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DetailRow(label: "network", value: "\(controller.chain.name) · \(controller.chain.id)")
            if let token = controller.draft.holding.token {
                DetailRow(label: "token", value: EthereumAddress.short(token.address))
            }
            DetailRow(label: "network fee", value: controller.networkFeeText ?? "…")
        }
        .padding(14)
        .toluCard(stroke: Tolu.Palette.line2)
    }
}

#Preview {
    TransferSignView(
        controller: TransferController(
            wallet: .preview,
            draft: TransferDraft(
                holding: Holding(chain: ChainRegistry.all[0], token: nil, balance: BigUInt(1_250_000_000_000_000_000)),
                recipient: "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf",
                amount: BigUInt(250_000_000_000_000_000),
                sendsMaximum: false
            )
        ),
        onBack: {},
        onDone: {}
    )
    .background(Tolu.Palette.ink)
    .preferredColorScheme(.dark)
}
