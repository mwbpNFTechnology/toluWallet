//
//  WalletListView.swift
//  toluWallet
//
//  Home, once unlocked: every wallet saved on this phone, and the way to
//  create another.
//

import SwiftUI

struct WalletListView: View {
    @Environment(Router.self) private var router
    @Environment(WalletStore.self) private var store

    var body: some View {
        ZStack {
            ToluBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        hero.padding(.bottom, 6)

                        if store.wallets.isEmpty {
                            emptyState
                        } else {
                            SectionHeader(title: "wallets", trailing: "\(store.wallets.count)")
                            ForEach(store.wallets) { wallet in
                                WalletCard(wallet: wallet) {
                                    router.push(.wallet(wallet.id))
                                }
                            }
                        }

                        if let draft = store.coldDraft {
                            pendingColdWallet(draft)
                        }

                        createButton(
                            "Create a wallet", systemImage: "plus", tint: Tolu.Palette.lime, route: .createWallet
                        )
                        .padding(.top, 2)
                        if store.coldDraft == nil {
                            createButton(
                                "Create with a cold device", systemImage: "snowflake",
                                tint: Tolu.Palette.violet, route: .createColdWallet
                            )
                        }
                    }
                    .padding(.horizontal, Tolu.Spacing.screen)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            ToluWordmark()
            Spacer()
            Button("Lock", systemImage: "lock.open") {
                router.popToRoot()
                store.lock()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Tolu.Palette.mute)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tolu.Spacing.screen)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("secp256k1 · keys stay on your tolu tag", color: Tolu.Palette.violet, tracking: 1.8)
            ToluHeading(text: "your wallets")
            Text("each wallet is a key on a tolu tag. the tag signs every transfer; this phone only keeps the slot and its password.")
                .font(.system(size: 13))
                .foregroundStyle(Tolu.Palette.mute)
                .lineSpacing(2)
                .frame(maxWidth: 330, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No wallets yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Tolu.Palette.text)
            Text("Create one and tap a tolu tag. The key is made inside the tag, or from a seed phrase you write down, and the address works on every EVM chain.")
                .font(.system(size: 13))
                .foregroundStyle(Tolu.Palette.mute)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toluCard()
    }

    private func createButton(_ title: String, systemImage: String, tint: Color, route: AppRoute) -> some View {
        Button {
            router.push(route)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(tint.opacity(0.5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }

    /// A cold wallet that was sent to the device and is waiting to be
    /// scanned and checked.
    private func pendingColdWallet(_ draft: ColdWalletDraft) -> some View {
        Button {
            router.push(.createColdWallet)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Tolu.Radius.control, style: .continuous)
                        .fill(Tolu.Palette.violet.opacity(0.1))
                    Image(systemName: "snowflake")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Tolu.Palette.violet)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.label)
                        .font(.toluTitle(18))
                        .tracking(-0.4)
                        .foregroundStyle(Tolu.Palette.text)
                        .lineLimit(1)
                    Text("Finish on the cold device, then scan its QR")
                        .font(.system(size: 12))
                        .foregroundStyle(Tolu.Palette.mute)
                        .multilineTextAlignment(.leading)
                    MonoLabel("slot 0x\(draft.keyObjectID) · not finished", size: 8.5, color: Tolu.Palette.amber, tracking: 1.2)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tolu.Palette.dim)
            }
            .padding(16)
            .toluCard(radius: Tolu.Radius.card, fill: Tolu.Palette.ink3, stroke: Tolu.Palette.violet.opacity(0.4))
        }
        .buttonStyle(PressableCardStyle())
    }
}

#Preview {
    NavigationStack {
        WalletListView()
            .environment(Router())
            .environment(WalletStore())
    }
    .preferredColorScheme(.dark)
}
