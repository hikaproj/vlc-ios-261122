//
//  VLCUltimateEngineHookable.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Strictly decoupled plugin interface for VLCPlayerViewController and VLCPlaybackService.
//

import Foundation
import CoreVideo
import Metal

/// Decoupled protocol for hosting or observing the VLC Ultimate Engine.
/// Conforming components in VLC can receive frame hooks, audio taps, and lifecycle state
/// without introducing circular dependencies or tight coupling.
@objc public protocol VLCUltimateEngineHookable: AnyObject {
    /// Called when the engine is attached to a player session.
    func ultimateEngineDidAttach(context: AnyObject?)
    
    /// Called when the engine is detached from a player session.
    func ultimateEngineDidDetach()
    
    /// Real-time audio buffer tap hook.
    /// - Parameters:
    ///   - samples: Raw 32-bit float audio buffer (interleaved or planar).
    ///   - count: Total number of samples in the buffer.
    ///   - channels: Channel count (1 for mono, 2 for stereo, etc.).
    ///   - sampleRate: Sampling rate in Hz (e.g. 44100, 48000).
    ///   - pts: Presentation timestamp in microseconds.
    func ultimateEngineDidReceiveAudioBuffer(
        samples: UnsafeMutablePointer<Float>,
        count: Int,
        channels: Int,
        sampleRate: Double,
        pts: Int64
    )
    
    /// Real-time zero-copy video frame tap hook.
    /// - Parameters:
    ///   - pixelBuffer: CVPixelBuffer received from decoder.
    ///   - pts: Presentation timestamp in microseconds.
    func ultimateEngineDidReceiveVideoPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        pts: Int64
    )
}

/// Notification keys used for zero-coupling inter-module communication.
public extension Notification.Name {
    /// Dispatched when the memory pressure or thermal status changes in `UltimateResourceCoordinator`.
    static let vlcUltimateResourcePressureDidChange = Notification.Name("vlcUltimateResourcePressureDidChange")
    
    /// Dispatched when audio FFT size must be resized due to thermal or memory pressure.
    static let vlcUltimateAudioFFTResizeRequested = Notification.Name("vlcUltimateAudioFFTResizeRequested")
    
    /// Dispatched when video pipeline precision must fallback (e.g. RGBA16Float -> BGRA8Unorm).
    static let vlcUltimateVideoPrecisionFallbackRequested = Notification.Name("vlcUltimateVideoPrecisionFallbackRequested")
    
    /// Dispatched when non-essential caches must be purged immediately.
    static let vlcUltimatePurgeNonEssentialCachesRequested = Notification.Name("vlcUltimatePurgeNonEssentialCachesRequested")
    
    /// Dispatched when dominant palette colors have been extracted from the current artwork/video frame.
    static let vlcUltimatePaletteUpdated = Notification.Name("vlcUltimatePaletteUpdated")
    
    /// Dispatched to update A/V lip-sync delay compensation.
    static let vlcUltimateLipSyncOffsetDidChange = Notification.Name("vlcUltimateLipSyncOffsetDidChange")
}

/// Information payload accompanying `vlcUltimatePaletteUpdated` notification.
public struct UltimatePalettePayload: Sendable {
    public let primaryColorHex: UInt32
    public let secondaryColorHex: UInt32
    public let tertiaryColorHex: UInt32
    public let accentColorHex: UInt32
    
    public init(primary: UInt32, secondary: UInt32, tertiary: UInt32, accent: UInt32) {
        self.primaryColorHex = primary
        self.secondaryColorHex = secondary
        self.tertiaryColorHex = tertiary
        self.accentColorHex = accent
    }
}
