//
//  UltimateNFCManager.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  CoreNFC NDEF Tag Automation for Instant Hardware Preset Loading and Writing.
//

import Foundation
import CoreNFC
import UIKit

public struct NFCDSPProfile: Codable, Sendable {
    public var dseeEnabled: Bool
    public var vinylEnabled: Bool
    public var spatialEnabled: Bool
    public var vocalRemoved: Bool
    public var sleepTimerMinutes: Int
    public var presetName: String
    
    public init(dsee: Bool, vinyl: Bool, spatial: Bool, vocalRemoved: Bool, sleepMinutes: Int, presetName: String) {
        self.dseeEnabled = dsee
        self.vinylEnabled = vinyl
        self.spatialEnabled = spatial
        self.vocalRemoved = vocalRemoved
        self.sleepTimerMinutes = sleepMinutes
        self.presetName = presetName
    }
}

@MainActor
public final class UltimateNFCManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    
    public static let shared = UltimateNFCManager()
    
    @Published public private(set) var isScanning = false
    @Published public private(set) var lastReadProfile: NFCDSPProfile?
    
    private var session: NFCNDEFReaderSession?
    private var profileToWrite: NFCDSPProfile?
    private var isWriteMode = false
    
    private override init() {
        super.init()
    }
    
    public var isNFCAvailable: Bool {
        return NFCNDEFReaderSession.readingAvailable
    }
    
    // MARK: - Scan NDEF Tag for Profile
    
    public func startScanningForPreset() {
        guard isNFCAvailable else { return }
        
        self.isWriteMode = false
        self.profileToWrite = nil
        
        let nfcSession = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: true
        )
        nfcSession.alertMessage = "Hold iPhone near NFC Tag to apply DSP Profile..."
        nfcSession.begin()
        self.session = nfcSession
        self.isScanning = true
    }
    
    // MARK: - Write Current Preset to NDEF Tag
    
    public func writeCurrentPreset(profile: NFCDSPProfile) {
        guard isNFCAvailable else { return }
        
        self.isWriteMode = true
        self.profileToWrite = profile
        
        let nfcSession = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: true
        )
        nfcSession.alertMessage = "Hold iPhone near writable NFC Tag to store profile..."
        nfcSession.begin()
        self.session = nfcSession
        self.isScanning = true
    }
    
    // MARK: - NFCNDEFReaderSessionDelegate
    
    public nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first,
              let record = message.records.first else {
            session.invalidate(errorMessage: "No NDEF record found.")
            return
        }
        
        let payloadData = record.payload
        // Skip UTF status byte if text record
        let data = payloadData.count > 3 ? payloadData.dropFirst(3) : payloadData
        
        if let profile = try? JSONDecoder().decode(NFCDSPProfile.self, from: data) {
            Task { @MainActor in
                self.applyProfile(profile)
                session.alertMessage = "Applied Profile: \(profile.presetName)"
                session.invalidate()
                UltimateHapticEngine.shared.playDetentSnap()
            }
        } else {
            session.invalidate(errorMessage: "Unrecognized NFC profile format.")
        }
    }
    
    public nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        
        Task { @MainActor in
            guard self.isWriteMode, let profile = self.profileToWrite else {
                session.connect(to: tag) { error in
                    if error != nil {
                        session.invalidate(errorMessage: "Failed to connect to NFC tag.")
                    }
                }
                return
            }
            
            // Connect and write
            session.connect(to: tag) { error in
                guard error == nil else {
                    session.invalidate(errorMessage: "Connection error.")
                    return
                }
                
                tag.queryNDEFStatus { status, capacity, error in
                    guard status == .readWrite, error == nil else {
                        session.invalidate(errorMessage: "Tag is not writable.")
                        return
                    }
                    
                    if let encoded = try? JSONEncoder().encode(profile),
                       let textPayload = NFCNDEFPayload.wellKnownTypeTextPayload(string: String(data: encoded, encoding: .utf8) ?? "", locale: .current) {
                        let ndefMessage = NFCNDEFMessage(records: [textPayload])
                        tag.writeNDEF(ndefMessage) { error in
                            if error == nil {
                                session.alertMessage = "Preset saved to NFC tag!"
                                session.invalidate()
                                Task { @MainActor in
                                    UltimateHapticEngine.shared.playDetentSnap()
                                }
                            } else {
                                session.invalidate(errorMessage: "Write failed.")
                            }
                        }
                    }
                }
            }
        }
    }
    
    public nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            self.session = nil
        }
    }
    
    public nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}
    
    private func applyProfile(_ profile: NFCDSPProfile) {
        self.lastReadProfile = profile
        let audio = UltimateAudioEngine.shared
        audio.dseeUltimateEnabled = profile.dseeEnabled
        audio.vinylProcessorEnabled = profile.vinylEnabled
        audio.spatialAudio714Enabled = profile.spatialEnabled
        audio.vocalRemoverEnabled = profile.vocalRemoved
    }
}
