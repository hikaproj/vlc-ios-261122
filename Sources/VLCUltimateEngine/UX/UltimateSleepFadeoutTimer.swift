//
//  UltimateSleepFadeoutTimer.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Logarithmic Sleep Fadeout Timer with 60s Dynamic Low-Pass Cutoff (20kHz -> 250Hz).
//

import Foundation
import UIKit
import Combine

@MainActor
public final class UltimateSleepFadeoutTimer: ObservableObject {
    
    public static let shared = UltimateSleepFadeoutTimer()
    
    @Published public private(set) var isTimerRunning = false
    @Published public private(set) var remainingSeconds: TimeInterval = 0
    @Published public private(set) var isFadeoutPhase = false
    
    private var timer: Timer?
    private var initialVolume: Float = 1.0
    private let fadeoutDuration: TimeInterval = 60.0
    
    private init() {}
    
    public func startSleepTimer(minutes: Int) {
        stopTimer()
        guard minutes > 0 else { return }
        
        self.remainingSeconds = TimeInterval(minutes * 60)
        self.isTimerRunning = true
        self.isFadeoutPhase = false
        
        // Prevent screen sleep during active playback countdown
        UIApplication.shared.isIdleTimerDisabled = true
        
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimerTick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
        UltimateHapticEngine.shared.playDetentSnap()
    }
    
    public func stopTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
        isFadeoutPhase = false
        remainingSeconds = 0
        
        // Restore volume
        NotificationCenter.default.post(
            name: Notification.Name("vlcUltimateSetVolumeRequested"),
            object: nil,
            userInfo: ["volume": 1.0]
        )
    }
    
    private func handleTimerTick() {
        guard remainingSeconds > 0 else {
            finalizeSleepAndLock()
            return
        }
        
        remainingSeconds -= 1.0
        
        // Final 60 seconds: Logarithmic Audio & Cutoff Fadeout
        if remainingSeconds <= fadeoutDuration {
            self.isFadeoutPhase = true
            let ratio = Float(remainingSeconds / fadeoutDuration) // 1.0 down to 0.0
            
            // Logarithmic volume decay
            let logVolume = max(0.0, min(1.0, log10(1.0 + 9.0 * ratio)))
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateSetVolumeRequested"),
                object: nil,
                userInfo: ["volume": logVolume]
            )
            
            // Sweep lowpass cutoff: 20000Hz down to 250Hz
            let cutoffHz = 250.0 + (20000.0 - 250.0) * pow(ratio, 2.0)
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateSetSleepCutoffRequested"),
                object: nil,
                userInfo: ["cutoffHz": cutoffHz]
            )
        }
    }
    
    private func finalizeSleepAndLock() {
        stopTimer()
        
        // 1. Pause playback
        NotificationCenter.default.post(name: Notification.Name("vlcUltimateTogglePlayPauseRequested"), object: nil)
        
        // 2. Allow iOS Idle Timer to turn off screen and lock device
        UIApplication.shared.isIdleTimerDisabled = false
        
        UltimateHapticEngine.shared.playDetentSnap()
    }
}
