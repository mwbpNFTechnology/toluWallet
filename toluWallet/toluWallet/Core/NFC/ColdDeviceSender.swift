//
//  ColdDeviceSender.swift
//  toluWallet
//
//  Talks to a toluCold device over NFC: hands it a new wallet's slots and
//  password, or tells it to cancel.
//
//  The phone stays the reader — an iPhone can't act as a card — and the
//  device's PN532 goes into card mode to listen. One short APDU says it all:
//
//      phone → SELECT F0746F6C75434F4C44     → 9000
//      phone → 80 20 00 00 <Lc> <setup>      → 9000      start a wallet
//      phone → 80 21 00 00                   → 9000      cancel
//
//  Only where the key will live and the password that will guard it cross
//  here. The key itself is made on the device and goes straight to the card.
//

import CoreNFC
import Foundation

final class ColdDeviceSender: NSObject {

    /// F0 = a proprietary AID, then "toluCOLD" in ASCII — listed in Info.plist
    /// so iOS will select it.
    private static let aid = Data([0xF0, 0x74, 0x6F, 0x6C, 0x75, 0x43, 0x4F, 0x4C, 0x44])
    private static let aidHex = aid.map { String(format: "%02X", $0) }.joined()

    private var session: NFCTagReaderSession?
    private var command: ColdDeviceCommand?
    private var doneMessage = ""
    private var continuation: CheckedContinuation<Void, Error>?

    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    /// Resumes once the device has accepted the setup, throws otherwise.
    func send(keyObjectID: [UInt8], passwordObjectID: [UInt8], password: [UInt8]) async throws {
        guard let payload = ColdSetupPayload.make(keyObjectID: keyObjectID, passwordObjectID: passwordObjectID,
                                                  password: password) else {
            throw ColdDeviceError.invalidSetup
        }
        try await perform(.setup(payload), alert: "Hold your phone to the toluCold reader",
                          doneMessage: "Sent. Now follow the device.")
    }

    /// Resumes once the device has taken the cancel: it erases what it holds
    /// and goes back to its start screen.
    func cancel() async throws {
        try await perform(.cancel, alert: "Hold your phone to the toluCold reader to cancel",
                          doneMessage: "Cancelled on the device.")
    }

    private func perform(_ command: ColdDeviceCommand, alert: String, doneMessage: String) async throws {
        guard NFCTagReaderSession.readingAvailable else { throw ColdDeviceError.unavailable }
        self.command = command
        self.doneMessage = doneMessage

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let session = NFCTagReaderSession(
                configuration: .init(pollingOption: .iso14443), delegate: self, queue: .main
            )
            session.alertMessage = alert
            self.session = session
            session.begin()
        }
    }

    // MARK: - Exchange

    private func deliver(to tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        guard let command else { return }
        Task {
            do {
                // iOS may have selected another of the app's AIDs while it
                // was discovering the tag; selecting ours is what starts the
                // conversation with the device.
                let select = NFCISO7816APDU(instructionClass: 0x00, instructionCode: 0xA4,
                                            p1Parameter: 0x04, p2Parameter: 0x00,
                                            data: Self.aid, expectedResponseLength: 256)
                let (_, selectSW1, selectSW2) = try await tag.sendCommand(apdu: select)
                guard selectSW1 == 0x90, selectSW2 == 0x00 else { throw ColdDeviceError.notAColdDevice }

                let request = NFCISO7816APDU(instructionClass: ColdDeviceCommand.instructionClass,
                                             instructionCode: command.instruction,
                                             p1Parameter: 0x00, p2Parameter: 0x00,
                                             data: command.data, expectedResponseLength: -1)
                let (_, sw1, sw2) = try await tag.sendCommand(apdu: request)
                guard sw1 == 0x90, sw2 == 0x00 else { throw ColdDeviceError.refused(sw1, sw2) }

                session.alertMessage = doneMessage
                session.invalidate()
                finish(.success(()))
            } catch {
                session.invalidate(errorMessage: (error as? LocalizedError)?.errorDescription ?? "The tap failed.")
                finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        session = nil
        command = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    /// The tag to talk to. The tolu card may be lying on the device's reader
    /// and answer too, so the one iOS selected by the device's AID is
    /// preferred over whichever came first.
    private func deviceTag(among tags: [NFCTag]) -> NFCTag? {
        let selectedAsDevice = tags.first { tag in
            guard case let .iso7816(isoTag) = tag else { return false }
            return isoTag.initialSelectedAID.caseInsensitiveCompare(Self.aidHex) == .orderedSame
        }
        return selectedAsDevice ?? tags.first
    }
}

extension ColdDeviceSender: NFCTagReaderSessionDelegate {

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // After a successful exchange this is just the session closing;
        // `finish` has already released the caller and ignores the second call.
        finish(.failure(error))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = deviceTag(among: tags) else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage: "Couldn't connect to the device.")
                self.finish(.failure(error))
                return
            }
            guard case let .iso7816(isoTag) = tag else {
                session.invalidate(errorMessage: ColdDeviceError.notAColdDevice.errorDescription ?? "")
                self.finish(.failure(ColdDeviceError.notAColdDevice))
                return
            }
            self.deliver(to: isoTag, session: session)
        }
    }
}
