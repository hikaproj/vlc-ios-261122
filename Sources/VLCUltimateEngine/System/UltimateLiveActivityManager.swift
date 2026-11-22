//
//  UltimateLiveActivityManager.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  ActivityKit & Dynamic Island Full Control with AppIntents for Background Execution.
//

import Foundation
import ActivityKit
import AppIntents
import SwiftUI

// MARK: - Activity Attributes & Content State

public struct UltimatePlayerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var artist: String
        public var currentTime: TimeInterval
        public var duration: TimeInterval
        public var isPlaying: Bool
        public var activeDspName: String
        public var isVocalRemoved: Bool
        public var isSilenceSkipActive: Bool
        
        public init(
            title: String,
            artist: String,
            currentTime: TimeInterval,
            duration: TimeInterval,
            isPlaying: Bool,
            activeDspName: String,
            isVocalRemoved: Bool,
            isSilenceSkipActive: Bool
        ) {
            self.title = title
            self.artist = artist
            self.currentTime = currentTime
            self.duration = duration
            self.isPlaying = isPlaying
            self.activeDspName = activeDspName
            self.isVocalRemoved = isVocalRemoved
            self.isSilenceSkipActive = isSilenceSkipActive
        }
    }
    
    public var mediaId: String
    
    public init(mediaId: String) {
        self.mediaId = mediaId
    }
}

// MARK: - Live Activity AppIntents (Background Execution)

public struct SkipTenSecondsIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Skip 10 Seconds"
    public static var isDiscoverable: Bool = false
    
    @Parameter(title: "Forward")
    public var forward: Bool
    
    public init() {
        self.forward = true
    }
    
    public init(forward: Bool) {
        self.forward = forward
    }
    
    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateSeekRelativeRequested"),
                object: nil,
                userInfo: ["offset": forward ? 10.0 : -10.0]
            )
        }
        return .result()
    }
}

public struct ToggleVocalRemoverIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Toggle Vocal Remover"
    public static var isDiscoverable: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            UltimateAudioEngine.shared.vocalRemoverEnabled.toggle()
        }
        return .result()
    }
}

public struct ToggleSilenceSkipIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Toggle Silence Skip"
    public static var isDiscoverable: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateToggleSilenceSkipRequested"),
                object: nil
            )
        }
        return .result()
    }
}

public struct MarkABPointIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Mark AB Loop Point"
    public static var isDiscoverable: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateMarkABPointRequested"),
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - Live Activity Manager

@MainActor
public final class UltimateLiveActivityManager: ObservableObject {
    
    public static let shared = UltimateLiveActivityManager()
    
    private var currentActivity: Activity<UltimatePlayerActivityAttributes>?
    
    private init() {}
    
    public func startLiveActivity(mediaId: String, title: String, artist: String, duration: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = UltimatePlayerActivityAttributes(mediaId: mediaId)
        let initialState = UltimatePlayerActivityAttributes.ContentState(
            title: title,
            artist: artist,
            currentTime: 0.0,
            duration: duration,
            isPlaying: true,
            activeDspName: "DSEE / Studio",
            isVocalRemoved: UltimateAudioEngine.shared.vocalRemoverEnabled,
            isSilenceSkipActive: false
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            self.currentActivity = activity
        } catch {
            self.currentActivity = nil
        }
    }
    
    public func updateLiveActivity(
        currentTime: TimeInterval,
        isPlaying: Bool,
        activeDspName: String,
        isVocalRemoved: Bool,
        isSilenceSkip: Bool
    ) {
        guard let activity = currentActivity else { return }
        
        var state = activity.content.state
        state.currentTime = currentTime
        state.isPlaying = isPlaying
        state.activeDspName = activeDspName
        state.isVocalRemoved = isVocalRemoved
        state.isSilenceSkipActive = isSilenceSkip
        
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
    
    public func endLiveActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.currentActivity = nil
    }
}
