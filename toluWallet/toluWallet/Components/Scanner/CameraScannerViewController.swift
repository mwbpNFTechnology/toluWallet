//
//  CameraScannerViewController.swift
//  toluWallet
//
//  A camera preview that reports the first QR code it sees. Ported from the
//  tolu app's pairing scanner; SwiftUI has no camera view of its own, so
//  this one piece is UIKit + AVFoundation.
//

import AVFoundation
import UIKit

final class CameraScannerViewController: UIViewController {

    /// Called once per appearance, with the code's text.
    var onCode: ((String) -> Void)?
    /// Called when the camera can't be used (permission refused, or no camera).
    var onUnavailable: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var didFire = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didFire = false
        Task {
            // Asks the first time; answers straight away after that.
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                onUnavailable?()
                return
            }
            if !isConfigured { isConfigured = configureSession() }
            guard isConfigured else {
                onUnavailable?()
                return
            }
            start()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func start() {
        guard !session.isRunning else { return }
        // startRunning blocks until the camera is up, so it stays off the main thread.
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
        return true
    }
}

extension CameraScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didFire,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        didFire = true
        onCode?(value)
    }

    /// Lets the next code through — after one that wasn't what was wanted.
    func resume() {
        didFire = false
    }
}
