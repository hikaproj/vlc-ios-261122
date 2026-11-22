//
//  UltimatePowerAndPiPManager.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Audio-Only Ultra Power Saver (Metal Suspend) & Custom Subtitle-Burned Picture-in-Picture.
//

import Foundation
import AVKit
import Metal
import CoreVideo
import UIKit

@MainActor
public final class UltimatePowerAndPiPManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    
    public static let shared = UltimatePowerAndPiPManager()
    
    // MARK: - Published State
    @Published public var isAudioOnlyPowerSaverActive: Bool = false {
        didSet { handlePowerSaverToggled() }
    }
    @Published public private(set) var isPictureInPictureActive: Bool = false
    
    // MARK: - PiP Handles
    private var pipController: AVPictureInPictureController?
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Audio-Only Ultra Power Saver
    
    private func handlePowerSaverToggled() {
        if isAudioOnlyPowerSaverActive {
            // 1. Suspend Metal pipelines and release texture memory to volatile state
            UltimateVideoPipeline.shared.heapManager.purgeTransientTextures()
            // 2. Disable CADisplayLink high-speed frame updates
            UltimateDisplayLinkDriver.shared.removeSubscriber(displayLinkSubscriber)
            // 3. Post notification to VLC core to drop video decoding
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateAudioOnlyModeChanged"),
                object: nil,
                userInfo: ["enabled": true]
            )
            UltimateHapticEngine.shared.playDetentSnap()
        } else {
            // Restore video pipeline
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateAudioOnlyModeChanged"),
                object: nil,
                userInfo: ["enabled": false]
            )
            UltimateHapticEngine.shared.playDetentSnap()
        }
    }
    
    private let displayLinkSubscriber = DummySubscriber()
    private final class DummySubscriber: UltimateDisplayLinkSubscriber {
        func displayLinkDidTick(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval) {}
    }
    
    // MARK: - Custom Subtitle-Burned Picture in Picture
    
    public func setupCustomPiP(with layer: AVSampleBufferDisplayLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        
        self.sampleBufferLayer = layer
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller
    }
    
    public func startPictureInPicture() {
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        pip.startPictureInPicture()
    }
    
    public func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }
    
    // MARK: - Enqueue Frame with Subtitle Burn-In
    
    public func enqueueFrame(pixelBuffer: CVPixelBuffer, subtitleText: String?) {
        guard let layer = sampleBufferLayer, !isAudioOnlyPowerSaverActive else { return }
        
        // Burn-in subtitle text if present
        if let subtitle = subtitleText, !subtitle.isEmpty {
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            
            if let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                // Render subtitle text banner at bottom
                UIGraphicsPushContext(ctx)
                let textRect = CGRect(x: 20, y: height - 80, width: width - 40, height: 60)
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 28),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3.0,
                    .paragraphStyle: style
                ]
                (subtitle as NSString).draw(in: textRect, withAttributes: attrs)
                UIGraphicsPopContext()
            }
        }
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        
        guard let format = formatDesc else { return }
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        
        if let sb = sampleBuffer, layer.isReadyForMoreMediaData {
            layer.enqueue(sb)
        }
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    public nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPictureInPictureActive = true }
    }
    
    public nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPictureInPictureActive = false }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension UltimatePowerAndPiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    public nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in
            NotificationCenter.default.post(name: Notification.Name("vlcUltimateTogglePlayPauseRequested"), object: nil)
        }
    }
    
    public nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: CMTime(seconds: 3600, preferredTimescale: 600))
    }
    
    public nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }
    
    public nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    
    public nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        let seconds = skipInterval.seconds
        Task { @MainActor in
            NotificationCenter.default.post(
                name: Notification.Name("vlcUltimateSeekRelativeRequested"),
                object: nil,
                userInfo: ["offset": seconds]
            )
        }
    }
}
