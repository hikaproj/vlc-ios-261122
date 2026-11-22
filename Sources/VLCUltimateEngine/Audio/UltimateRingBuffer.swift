//
//  UltimateRingBuffer.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Zero-overhead Swift 6 wrapper utilizing @_silgen_name direct C-ABI binding.
//

import Foundation

// MARK: - Direct C-ABI Bindings via @_silgen_name

@_silgen_name("ultimate_ringbuffer_create")
private func c_ultimate_ringbuffer_create(_ capacityFrames: Int, _ channels: Int) -> OpaquePointer?

@_silgen_name("ultimate_ringbuffer_destroy")
private func c_ultimate_ringbuffer_destroy(_ handle: OpaquePointer?)

@_silgen_name("ultimate_ringbuffer_write")
private func c_ultimate_ringbuffer_write(_ handle: OpaquePointer?, _ data: UnsafePointer<Float>?, _ sampleCount: Int) -> Int

@_silgen_name("ultimate_ringbuffer_read")
private func c_ultimate_ringbuffer_read(_ handle: OpaquePointer?, _ destination: UnsafeMutablePointer<Float>?, _ sampleCount: Int) -> Int

@_silgen_name("ultimate_ringbuffer_available_read")
private func c_ultimate_ringbuffer_available_read(_ handle: OpaquePointer?) -> Int

@_silgen_name("ultimate_ringbuffer_available_write")
private func c_ultimate_ringbuffer_available_write(_ handle: OpaquePointer?) -> Int

@_silgen_name("ultimate_ringbuffer_reset")
private func c_ultimate_ringbuffer_reset(_ handle: OpaquePointer?)

@_silgen_name("ultimate_audio_calculate_group_delay_ms")
private func c_ultimate_audio_calculate_group_delay_ms(_ currentFftSize: Int32, _ rubberBandLatencySamples: Int, _ sampleRate: Double) -> Double

// MARK: - Swift High-Performance Wrapper

/// Swift high-level wrapper over the C++17 Cache-Line Aligned SPSC RingBuffer.
/// Optimized for real-time streaming between decoder callbacks and DSP pipelines.
public final class UltimateRingBuffer: @unchecked Sendable {
    private var rawHandle: OpaquePointer?
    public let capacityFrames: Int
    public let channels: Int
    
    /// Initializes an aligned ring buffer.
    /// - Parameters:
    ///   - capacityFrames: Buffer size in frames (e.g. 16384).
    ///   - channels: Number of channels (e.g. 2 for stereo).
    public init?(capacityFrames: Int = 16384, channels: Int = 2) {
        guard let handle = c_ultimate_ringbuffer_create(capacityFrames, channels) else {
            return nil
        }
        self.rawHandle = handle
        self.capacityFrames = capacityFrames
        self.channels = channels
    }
    
    deinit {
        if let handle = rawHandle {
            c_ultimate_ringbuffer_destroy(handle)
            rawHandle = nil
        }
    }
    
    /// Writes raw audio samples into the ring buffer. Zero allocation.
    /// Must be called from the Producer thread.
    @inline(__always)
    @discardableResult
    public func write(samples: UnsafePointer<Float>, count: Int) -> Int {
        guard let handle = rawHandle else { return 0 }
        return c_ultimate_ringbuffer_write(handle, samples, count)
    }
    
    /// Writes an array of Float samples.
    @inline(__always)
    @discardableResult
    public func write(samples: [Float]) -> Int {
        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return write(samples: baseAddress, count: buffer.count)
        }
    }
    
    /// Reads audio samples into a destination pointer. Zero allocation.
    /// Must be called from the Consumer thread.
    @inline(__always)
    @discardableResult
    public func read(destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        guard let handle = rawHandle else { return 0 }
        return c_ultimate_ringbuffer_read(handle, destination, count)
    }
    
    /// Number of available samples ready to be read.
    @inline(__always)
    public var availableRead: Int {
        guard let handle = rawHandle else { return 0 }
        return c_ultimate_ringbuffer_available_read(handle)
    }
    
    /// Number of sample slots ready to accept writes.
    @inline(__always)
    public var availableWrite: Int {
        guard let handle = rawHandle else { return 0 }
        return c_ultimate_ringbuffer_available_write(handle)
    }
    
    /// Clears indices. Only invoke when audio processing is halted.
    public func reset() {
        guard let handle = rawHandle else { return }
        c_ultimate_ringbuffer_reset(handle)
    }
    
    /// Calculates cumulative DSP group delay in milliseconds for lip-sync correction.
    public static func calculateGroupDelayMs(
        fftWindowSize: Int,
        rubberBandLatencySamples: Int,
        sampleRate: Double
    ) -> Double {
        return c_ultimate_audio_calculate_group_delay_ms(
            Int32(fftWindowSize),
            rubberBandLatencySamples,
            sampleRate
        )
    }
}
