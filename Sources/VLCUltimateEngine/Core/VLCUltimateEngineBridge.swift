//
//  VLCUltimateEngineBridge.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Zero-Invasion Interop Bridge connecting VLCPlaybackService to VLCUltimateEngine via NotificationCenter.
//

import Foundation
import UIKit
import CoreVideo

@MainActor
public final class VLCUltimateEngineBridge: NSObject {
    
    public static let shared = VLCUltimateEngineBridge()
    
    private var isHooked = false
    private let playbackService = PlaybackService.sharedInstance()
    
    private override init() {
        super.init()
    }
    
    /// Attaches the VLC Ultimate Engine to the running VLC application.
    /// Call this once in AppDelegate or when the player view controller is instantiated.
    public func attach() {
        guard !isHooked else { return }
        isHooked = true
        
        setupNotificationBridges()
        setupCommandBridges()
        
        // Start resource coordination
        UltimateResourceCoordinator.shared.startPeriodicMonitoring()
    }
    
    public func detach() {
        guard isHooked else { return }
        isHooked = false
        NotificationCenter.default.removeObserver(self)
        UltimateResourceCoordinator.shared.stopPeriodicMonitoring()
    }
    
    // MARK: - VLC Playback Service Observers
    
    private func setupNotificationBridges() {
        // Observe playback state change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: NSNotification.Name("VLCPlaybackServicePlaybackDidPause"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: NSNotification.Name("VLCPlaybackServicePlaybackDidResume"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaChanged),
            name: NSNotification.Name("VLCPlaybackServiceMediaChanged"),
            object: nil
        )
    }
    
    @objc private func handlePlaybackStateChanged() {
        let isPlaying = playbackService.isPlaying
        let title = playbackService.currentlyPlayingMedia?.metaDictionary[VLCMetaInformationTitle] as? String ?? "Media"
        let artist = playbackService.currentlyPlayingMedia?.metaDictionary[VLCMetaInformationArtist] as? String ?? "VLC Ultimate"
        let duration = TimeInterval(playbackService.mediaDuration) / 1000.0
        let currentTime = TimeInterval(playbackService.playedTime?.value?.doubleValue ?? 0.0) / 1000.0
        
        UltimateLiveActivityManager.shared.updateLiveActivity(
            currentTime: currentTime,
            isPlaying: isPlaying,
            activeDspName: "DSEE / Spatial",
            isVocalRemoved: UltimateAudioEngine.shared.vocalRemoverEnabled,
            isSilenceSkip: false
        )
    }
    
    @objc private func handleMediaChanged() {
        guard let currentMedia = playbackService.currentlyPlayingMedia,
              let mediaURL = currentMedia.url else { return }
        
        // 1. Restore per-folder playback settings automatically from SQLite
        let savedSettings = UltimateFolderSettingsStore.shared.loadSettings(for: mediaURL)
        playbackService.playbackRate = savedSettings.playbackRate
        playbackService.audioDelay = Float(savedSettings.audioDelayMs)
        playbackService.subtitleDelay = Float(savedSettings.subtitleDelayMs)
        
        let audio = UltimateAudioEngine.shared
        audio.dseeUltimateEnabled = savedSettings.dseeEnabled
        audio.vinylProcessorEnabled = savedSettings.vinylEnabled
        audio.spatialAudio714Enabled = savedSettings.spatialEnabled
        
        let video = UltimateVideoPipeline.shared
        video.hdrToneMappingEnabled = savedSettings.hdrToneMappingEnabled
        video.anime4kSharpenEnabled = savedSettings.anime4kEnabled
        video.retroCrtEnabled = savedSettings.crtEnabled
        
        // 2. Scan Waveform & Silence in background
        let asset = AVAsset(url: mediaURL)
        UltimateWaveformScanner.shared.scanWaveform(from: asset, assetURL: mediaURL) { points, intervals in
            // Pre-cached for waveform scrubbing
        }
        
        // 3. Start Live Activity
        let title = currentMedia.metaDictionary[VLCMetaInformationTitle] as? String ?? mediaURL.lastPathComponent
        let artist = currentMedia.metaDictionary[VLCMetaInformationArtist] as? String ?? "VLC"
        let duration = TimeInterval(playbackService.mediaDuration) / 1000.0
        
        UltimateLiveActivityManager.shared.startLiveActivity(
            mediaId: mediaURL.absoluteString,
            title: title,
            artist: artist,
            duration: duration
        )
    }
    
    // MARK: - Inbound Command Bridges (From Remote, Intents, Timers)
    
    private func setupCommandBridges() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("vlcUltimateTogglePlayPauseRequested"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.playbackService.playPause()
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("vlcUltimateSeekRelativeRequested"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let offset = notif.userInfo?["offset"] as? Double else { return }
            if offset > 0 {
                self.playbackService.jumpForward(Int32(offset))
            } else {
                self.playbackService.jumpBackward(Int32(abs(offset)))
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("vlcUltimateLipSyncOffsetDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let delayMs = notif.userInfo?["delayMs"] as? Double else { return }
            self.playbackService.audioDelay = Float(delayMs)
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("vlcUltimateSetPlaybackRateRequested"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let rate = notif.userInfo?["rate"] as? Float else { return }
            self.playbackService.playbackRate = rate
        }
    }
}
