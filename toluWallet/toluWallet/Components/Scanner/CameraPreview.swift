//
//  CameraPreview.swift
//  toluWallet
//
//  The SwiftUI face of `CameraScannerViewController`.
//

import SwiftUI

struct CameraPreview: UIViewControllerRepresentable {
    /// Return `true` to accept the code; `false` keeps scanning.
    let onCode: (String) -> Bool
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> CameraScannerViewController {
        let controller = CameraScannerViewController()
        controller.onCode = { [weak controller] code in
            if !onCode(code) { controller?.resume() }
        }
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ controller: CameraScannerViewController, context: Context) {}
}
