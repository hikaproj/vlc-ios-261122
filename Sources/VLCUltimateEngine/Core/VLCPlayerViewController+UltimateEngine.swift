//
//  VLCPlayerViewController+UltimateEngine.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Non-Invasive Extension on PlayerViewController adding Studio Controls, Karaoke, and Shaders.
//

import UIKit
import SwiftUI
import CoreVideo

extension PlayerViewController: VLCUltimateEngineHookable {
    
    // MARK: - Engine Attachment Hook
    
    @objc public func attachUltimateEngine() {
        VLCUltimateEngineBridge.shared.attach()
        addStudioWorkstationToolbarButton()
    }
    
    // MARK: - Studio Workstation Toolbar Button
    
    private func addStudioWorkstationToolbarButton() {
        let studioButton = UIButton(type: .system)
        studioButton.setImage(UIImage(systemName: "dial.low.fill"), for: .normal)
        studioButton.tintColor = UIColor(red: 0.40, green: 0.988, blue: 0.945, alpha: 1.0) // Neon Teal
        studioButton.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.75)
        studioButton.layer.cornerRadius = 20
        studioButton.layer.borderWidth = 1.0
        studioButton.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        studioButton.translatesAutoresizingMaskIntoConstraints = false
        
        studioButton.addTarget(self, action: #selector(handleStudioButtonPressed), for: .touchUpInside)
        
        view.addSubview(studioButton)
        NSLayoutConstraint.activate([
            studioButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            studioButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            studioButton.widthAnchor.constraint(equalToConstant: 40),
            studioButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    @objc private func handleStudioButtonPressed() {
        UltimateHapticEngine.shared.playJogTick()
        presentStudioWorkstationSheet()
    }
    
    // MARK: - Present Studio Workstation Modal
    
    public func presentStudioWorkstationSheet() {
        let hostingController = UIHostingController(rootView: UltimateAudioMixerUI())
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(hostingController, animated: true)
    }
    
    // MARK: - Present Secret Calculator Vault Modal
    
    public func presentSecretVaultModal() {
        let vaultView = UltimateSecretVaultView()
        let hostingController = UIHostingController(rootView: vaultView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }
    
    // MARK: - VLCUltimateEngineHookable Conformance
    
    public func ultimateEngineDidAttach(context: AnyObject?) {
        // Initialized
    }
    
    public func ultimateEngineDidDetach() {
        VLCUltimateEngineBridge.shared.detach()
    }
    
    public func ultimateEngineDidReceiveAudioBuffer(
        samples: UnsafeMutablePointer<Float>,
        count: Int,
        channels: Int,
        sampleRate: Double,
        pts: Int64
    ) {
        // Feed directly into real-time Lock-Free DSP Chain
        let frames = count / max(1, channels)
        UltimateAudioEngine.shared.processAudioFrames(samples: samples, frameCount: frames)
    }
    
    public func ultimateEngineDidReceiveVideoPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        pts: Int64
    ) {
        // Enqueue to PiP if active
        if UltimatePowerAndPiPManager.shared.isPictureInPictureActive {
            UltimatePowerAndPiPManager.shared.enqueueFrame(pixelBuffer: pixelBuffer, subtitleText: nil)
        }
    }
}
