//
//  TransferFlowView.swift
//  toluWallet
//
//  The two transfer screens — details, then sign — presented over the wallet.
//

import SwiftUI

struct TransferFlowView: View {
    let onClose: () -> Void
    /// Called once a transaction has gone out, so the wallet can reload.
    let onSent: () -> Void

    @State private var form: TransferFormModel
    @State private var controller: TransferController?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(wallet: WalletRecord, holdings: [Holding],
         onClose: @escaping () -> Void, onSent: @escaping () -> Void) {
        self.onClose = onClose
        self.onSent = onSent
        _form = State(initialValue: TransferFormModel(wallet: wallet, holdings: holdings))
    }

    var body: some View {
        ZStack {
            ToluBackground()
            if let controller {
                TransferSignView(controller: controller, onBack: { leaveSigning(controller) }, onDone: finish)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                TransferDetailsView(form: form, onBack: onClose) { draft in
                    show(TransferController(wallet: form.wallet, draft: draft))
                }
            }
        }
    }

    private func show(_ controller: TransferController?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            self.controller = controller
        }
    }

    /// Before the broadcast, back returns to the form. After it there is
    /// nothing left to edit, so it closes.
    private func leaveSigning(_ controller: TransferController) {
        guard !controller.hasBroadcast else { finish(); return }
        controller.cancel()
        show(nil)
    }

    private func finish() {
        if controller?.hasBroadcast == true { onSent() }
        onClose()
    }
}

#Preview {
    TransferFlowView(wallet: .preview, holdings: [], onClose: {}, onSent: {})
        .preferredColorScheme(.dark)
}
