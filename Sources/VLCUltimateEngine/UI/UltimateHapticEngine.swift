//
//  UltimateHapticEngine.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  CoreHaptics Taptic Engine Driver for Studio Knobs, Detents, and Sub-Bass Transients.
//

import Foundation
import CoreHaptics
import UIKit

/// Manages real-time physical tactile feedback using CoreHaptics (CHHapticEngine).
/// Designed for studio jog dials, snap points, and audio-reactive sub-bass vibration.
public final class UltimateHapticEngine: @unchecked Sendable {
    
    public static let shared = UltimateHapticEngine()
    
    private var hapticEngine: CHHapticEngine?
    private let engineLock = NSLock()
    private var isEngineRunning = false
    private let supportsHaptics: Bool
    
    // Fallback generators for older devices or low-power modes
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    private let impactFeedbackHeavy = UIImpactFeedbackGenerator(style: .heavy)
    
    private init() {
        self.supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        if supportsHaptics {
            setupHapticEngine()
        }
        selectionFeedback.prepare()
        impactFeedbackLight.prepare()
        impactFeedbackHeavy.prepare()
    }
    
    deinit {
        stopEngine()
    }
    
    // MARK: - Engine Initialization & Recovery
    
    private func setupHapticEngine() {
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            
            engine.resetHandler = { [weak self] in
                guard let self = self else { return }
                self.engineLock.lock()
                defer { self.engineLock.unlock() }
                do {
                    try self.hapticEngine?.start()
                    self.isEngineRunning = true
                } catch {
                    self.isEngineRunning = false
                }
            }
            
            engine.stoppedHandler = { [weak self] reason in
                guard let self = self else { return }
                self.engineLock.lock()
                self.isEngineRunning = false
                self.engineLock.unlock()
            }
            
            self.hapticEngine = engine
        } catch {
            self.hapticEngine = nil
        }
    }
    
    private func ensureEngineRunning() -> Bool {
        engineLock.lock()
        defer { engineLock.unlock() }
        
        guard let engine = hapticEngine else { return false }
        if !isEngineRunning {
            do {
                try engine.start()
                isEngineRunning = true
            } catch {
                isEngineRunning = false
                return false
            }
        }
        return isEngineRunning
    }
    
    public func stopEngine() {
        engineLock.lock()
        defer { engineLock.unlock() }
        
        hapticEngine?.stop(completionHandler: nil)
        isEngineRunning = false
    }
    
    // MARK: - Studio Control Haptic Patterns
    
    /// Precision Jog Dial Tick (frame-by-frame scrubbing).
    public func playJogTick(intensity: Float = 0.55, sharpness: Float = 0.85) {
        guard supportsHaptics, ensureEngineRunning(), let engine = hapticEngine else {
            DispatchQueue.main.async { [weak self] in
                self?.selectionFeedback.selectionChanged()
            }
            return
        }
        
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: max(0.1, min(1.0, intensity))),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: max(0.1, min(1.0, sharpness)))
            ],
            relativeTime: 0
        )
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.selectionFeedback.selectionChanged()
            }
        }
    }
    
    /// Detent Snap (magnetic snap to center, 0-point, or marker).
    public func playDetentSnap() {
        guard supportsHaptics, ensureEngineRunning(), let engine = hapticEngine else {
            DispatchQueue.main.async { [weak self] in
                self?.impactFeedbackHeavy.impactOccurred()
            }
            return
        }
        
        let primary = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.95),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.70)
            ],
            relativeTime: 0
        )
        let rebound = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.40),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.90)
            ],
            relativeTime: 0.04
        )
        
        do {
            let pattern = try CHHapticPattern(events: [primary, rebound], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.impactFeedbackHeavy.impactOccurred()
            }
        }
    }
    
    /// Audio Reactive Bass Transient Vibration.
    /// Modulated by the 4th-order Butterworth low-pass filter envelope (<75Hz).
    /// - Parameters:
    ///   - intensity: Normalized transient energy (0.0 ... 1.0).
    ///   - sharpness: Transient punchiness (0.0 ... 1.0).
    public func playBassTransient(intensity: Float, sharpness: Float = 0.35) {
        guard intensity > 0.05 else { return }
        
        guard supportsHaptics, ensureEngineRunning(), let engine = hapticEngine else {
            if intensity > 0.6 {
                DispatchQueue.main.async { [weak self] in
                    self?.impactFeedbackLight.impactOccurred(intensity: CGFloat(intensity))
                }
            }
            return
        }
        
        let clampedIntensity = max(0.1, min(1.0, intensity))
        let clampedSharpness = max(0.1, min(1.0, sharpness))
        
        let transient = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clampedSharpness)
            ],
            relativeTime: 0
        )
        
        do {
            let pattern = try CHHapticPattern(events: [transient], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Drop frame smoothly if audio thread transient fires too rapidly
        }
    }
}
