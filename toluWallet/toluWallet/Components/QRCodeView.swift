//
//  QRCodeView.swift
//  toluWallet
//
//  Renders text as a QR code on a light tile, so any camera can read it
//  against the dark interface.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let text: String
    var side: CGFloat = 208

    var body: some View {
        Group {
            if let image = Self.makeImage(from: text) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .padding(14)
                    .background(Tolu.Palette.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Tolu.Palette.ink2)
                    .frame(width: side + 28, height: side + 28)
                    .overlay(MonoLabel("qr unavailable", size: 9, color: Tolu.Palette.dim, tracking: 1.4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("QR code")
    }

    private static func makeImage(from text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // M: survives a scuffed screen or a phone held at an angle.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

#Preview {
    QRCodeView(text: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf")
        .padding()
        .background(Tolu.Palette.ink)
}
