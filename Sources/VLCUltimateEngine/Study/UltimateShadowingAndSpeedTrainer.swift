//
//  UltimateShadowingAndSpeedTrainer.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Automated Shadowing Recorder with Turn-Taking Playback and Incremental Loop Speed Trainer.
//

import Foundation
import AVFoundation

public enum ShadowingState: Sendable {
    case idle
    case playingModelPhrase
    case recordingUserVoice(remainingSeconds: TimeInterval)
    case playingBackComparison
}

@MainActor
public final class UltimateShadowingAndSpeedTrainer: ObservableObject {
    
    public static let shared = UltimateShadowingAndSpeedTrainer()
    
    // MARK: - Published Properties
    @Published public var isShadowingModeEnabled: Bool = false
    @Published public private(set) var shadowingState: ShadowingState = .idle
    
    @Published public var isSpeedTrainerEnabled: Bool = false
    @Published public var initialSpeed: Float = 0.70
    @Published public var speedStepIncrement: Float = 0.10
    @Published public var maxSpeed: Float = 1.00
    @Published public private(set) var currentSpeed: Float = 0.70
    @Published public private(set) var completedLoopCount: Int = 0
    
    // MARK: - Audio Recorder State
    private var audioRecorder: AVAudioRecorder?
    private var recordedAudioURL: URL?
    private var comparisonPlayer: AVAudioPlayer?
    
    private init() {
        let tempDir = FileManager.default.temporaryDirectory
        self.recordedAudioURL = tempDir.appendingPathComponent("shadowing_user_voice.m4a")
    }
    
    // MARK: - Speed Trainer Logic
    
    public func resetSpeedTrainer() {
        currentSpeed = initialSpeed
        completedLoopCount = 0
    }
    
    public func handleABLoopCompleted() -> Float {
        guard isSpeedTrainerEnabled else { return 1.0 }
        completedLoopCount += 1
        
        let newSpeed = min(maxSpeed, currentSpeed + speedStepIncrement)
        if newSpeed != currentSpeed {
            currentSpeed = newSpeed
            UltimateHapticEngine.shared.playDetentSnap()
        }
        return currentSpeed
    }
    
    // MARK: - Shadowing Auto-Record & Comparison Logic
    
    public func handleSubtitlePhraseEnded(phraseDuration: TimeInterval, onPauseVideo: () -> Void) {
        guard isShadowingModeEnabled else { return }
        
        onPauseVideo()
        startRecording(duration: max(1.5, phraseDuration * 1.2))
    }
    
    private func startRecording(duration: TimeInterval) {
        guard let url = recordedAudioURL else { return }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record(forDuration: duration)
            self.audioRecorder = recorder
            self.shadowingState = .recordingUserVoice(remainingSeconds: duration)
            
            UltimateHapticEngine.shared.playJogTick(intensity: 0.8)
            
            // Countdown Timer to transition to comparison playback
            Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopRecordingAndPlayComparison()
                }
            }
        } catch {
            self.shadowingState = .idle
        }
    }
    
    private func stopRecordingAndPlayComparison() {
        audioRecorder?.stop()
        audioRecorder = nil
        
        guard let url = recordedAudioURL, FileManager.default.fileExists(atPath: url.path) else {
            shadowingState = .idle
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.comparisonPlayer = player
            self.shadowingState = .playingBackComparison
            
            Timer.scheduledTimer(withTimeInterval: player.duration + 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.shadowingState = .idle
                }
            }
        } catch {
            shadowingState = .idle
        }
    }
}
