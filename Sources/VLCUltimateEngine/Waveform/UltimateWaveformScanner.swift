//
//  UltimateWaveformScanner.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Ultra-Fast AVAssetReader Waveform Scanner, Binary Caching, Highlight Heatmap, and Silence Detection.
//

import Foundation
import AVFoundation
import Accelerate

public struct WaveformPoint: Sendable {
    public let rms: Float
    public let peak: Float
    public let highlightScore: Float // 0.0 (cold teal) to 1.0 (blazing orange)
    public let isSilent: Bool
    
    public init(rms: Float, peak: Float, highlightScore: Float, isSilent: Bool) {
        self.rms = rms
        self.peak = peak
        self.highlightScore = highlightScore
        self.isSilent = isSilent
    }
}

public struct SilenceInterval: Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    
    public var duration: TimeInterval { endTime - startTime }
}

public final class UltimateWaveformScanner: @unchecked Sendable {
    
    public static let shared = UltimateWaveformScanner()
    
    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "org.videolan.vlc.ultimate.waveform.scanner", qos: .userInitiated)
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("UltimateWaveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Binary Cache Operations
    
    private func cacheURL(for assetURL: URL) -> URL {
        let filename = assetURL.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "waveform"
        return cacheDirectory.appendingPathComponent("\(filename).bin")
    }
    
    public func loadCachedWaveform(for assetURL: URL) -> [WaveformPoint]? {
        let url = cacheURL(for: assetURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        let pointSize = MemoryLayout<Float>.size * 3 + MemoryLayout<UInt8>.size
        let count = data.count / pointSize
        guard count > 0 else { return nil }
        
        var points: [WaveformPoint] = []
        points.reserveCapacity(count)
        
        data.withUnsafeBytes { raw in
            var offset = 0
            for _ in 0..<count {
                let rms = raw.load(fromByteOffset: offset, as: Float.self)
                let peak = raw.load(fromByteOffset: offset + 4, as: Float.self)
                let score = raw.load(fromByteOffset: offset + 8, as: Float.self)
                let silentByte = raw.load(fromByteOffset: offset + 12, as: UInt8.self)
                points.append(WaveformPoint(rms: rms, peak: peak, highlightScore: score, isSilent: silentByte != 0))
                offset += pointSize
            }
        }
        return points
    }
    
    private func saveCachedWaveform(_ points: [WaveformPoint], for assetURL: URL) {
        let url = cacheURL(for: assetURL)
        var data = Data(capacity: points.count * 13)
        for p in points {
            var rms = p.rms
            var peak = p.peak
            var score = p.highlightScore
            var silent: UInt8 = p.isSilent ? 1 : 0
            withUnsafeBytes(of: &rms) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &peak) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &score) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &silent) { data.append(contentsOf: $0) }
        }
        try? data.write(to: url, options: .atomic)
    }
    
    // MARK: - Background Parallel Scanning
    
    public func scanWaveform(
        from asset: AVAsset,
        assetURL: URL,
        targetPoints: Int = 1200,
        silenceThresholdDb: Float = -45.0,
        minSilenceDuration: TimeInterval = 0.40,
        completion: @escaping @Sendable ([WaveformPoint], [SilenceInterval]) -> Void
    ) {
        if let cached = loadCachedWaveform(for: assetURL) {
            let intervals = computeSilenceIntervals(from: cached, duration: asset.duration.seconds, minSilenceDuration: minSilenceDuration)
            completion(cached, intervals)
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            guard let reader = try? AVAssetReader(asset: asset),
                  let audioTrack = asset.tracks(withMediaType: .audio).first else {
                completion([], [])
                return
            }
            
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 16000.0 // Downsample to 16kHz for lightning-fast scan
            ]
            
            let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            trackOutput.alwaysCopiesSampleData = false
            reader.add(trackOutput)
            
            guard reader.startReading() else {
                completion([], [])
                return
            }
            
            var allSamples: [Float] = []
            while reader.status == .reading {
                guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                      let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { break }
                
                let length = CMBlockBufferGetDataLength(blockBuffer)
                let sampleCount = length / MemoryLayout<Float>.size
                let currentCount = allSamples.count
                allSamples.resize(to: currentCount + sampleCount)
                
                allSamples.withUnsafeMutableBufferPointer { ptr in
                    guard let base = ptr.baseAddress else { return }
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base.advanced(by: currentCount))
                }
            }
            
            let totalCount = allSamples.count
            guard totalCount > 0 else {
                completion([], [])
                return
            }
            
            // Downsample into targetPoints buckets
            let bucketSize = max(1, totalCount / targetPoints)
            let actualPoints = totalCount / bucketSize
            var points: [WaveformPoint] = []
            points.reserveCapacity(actualPoints)
            
            let silenceLinearThreshold = pow(10.0, silenceThresholdDb / 20.0)
            var prevEnergy: Float = 0.0
            
            for b in 0..<actualPoints {
                let start = b * bucketSize
                let end = min(totalCount, start + bucketSize)
                let count = end - start
                
                var rms: Float = 0.0
                var peak: Float = 0.0
                
                allSamples.withUnsafeBufferPointer { buf in
                    guard let base = buf.baseAddress else { return }
                    let subBase = base.advanced(by: start)
                    vDSP_rmsqv(subBase, 1, &rms, vDSP_Length(count))
                    vDSP_maxmgv(subBase, 1, &peak, vDSP_Length(count))
                }
                
                // Highlight Score via Short-Term Energy Flux
                let energy = rms * rms
                let flux = max(0.0, energy - prevEnergy)
                prevEnergy = energy
                
                let highlightScore = min(1.0, (energy * 4.0 + flux * 12.0))
                let isSilent = rms < silenceLinearThreshold
                
                points.append(WaveformPoint(
                    rms: rms,
                    peak: peak,
                    highlightScore: highlightScore,
                    isSilent: isSilent
                ))
            }
            
            self.saveCachedWaveform(points, for: assetURL)
            let duration = asset.duration.seconds
            let intervals = self.computeSilenceIntervals(from: points, duration: duration, minSilenceDuration: minSilenceDuration)
            
            DispatchQueue.main.async {
                completion(points, intervals)
            }
        }
    }
    
    private func computeSilenceIntervals(
        from points: [WaveformPoint],
        duration: TimeInterval,
        minSilenceDuration: TimeInterval
    ) -> [SilenceInterval] {
        guard points.count > 0 && duration > 0 else { return [] }
        let secPerPoint = duration / Double(points.count)
        
        var intervals: [SilenceInterval] = []
        var inSilence = false
        var startIndex: Int = 0
        
        for (i, p) in points.enumerated() {
            if p.isSilent && !inSilence {
                inSilence = true
                startIndex = i
            } else if !p.isSilent && inSilence {
                inSilence = false
                let silDuration = Double(i - startIndex) * secPerPoint
                if silDuration >= minSilenceDuration {
                    intervals.append(SilenceInterval(
                        startTime: Double(startIndex) * secPerPoint,
                        endTime: Double(i) * secPerPoint
                    ))
                }
            }
        }
        
        if inSilence {
            let silDuration = Double(points.count - startIndex) * secPerPoint
            if silDuration >= minSilenceDuration {
                intervals.append(SilenceInterval(
                    startTime: Double(startIndex) * secPerPoint,
                    endTime: duration
                ))
            }
        }
        
        return intervals
    }
}

private extension Array {
    mutating func resize(to newCount: Int) where Element == Float {
        if count < newCount {
            append(contentsOf: repeatElement(0.0, count: newCount - count))
        } else if count > newCount {
            removeSubrange(newCount..<count)
        }
    }
}
