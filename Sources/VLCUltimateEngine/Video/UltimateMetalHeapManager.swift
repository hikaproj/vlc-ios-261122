//
//  UltimateMetalHeapManager.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Zero-Allocation Metal Texture Heap & Memory Aliasing Manager under strict 120MB budget.
//

import Foundation
import Metal
import CoreVideo
import Combine

/// Manages pre-allocated MTLHeap memory and texture aliasing for the video compute pipeline.
/// Guarantees that frame-by-frame MTLTexture allocations are strictly zero, staying under 120MB VRAM budget.
public final class UltimateMetalHeapManager: @unchecked Sendable {
    
    // MARK: - Memory Budget Constants
    public static let maxHeapBudgetBytes: Int = 110 * 1024 * 1024 // 110MB heap (well under 120MB hard ceiling)
    
    // MARK: - Core Metal Handles
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    
    private let heapLock = NSLock()
    private var heap: MTLHeap?
    
    // MARK: - Texture Descriptors & Formats
    public private(set) var isHighPrecision: Bool = true
    public private(set) var activePixelFormat: MTLPixelFormat = .rgba16Float
    
    // Cached Textures allocated from the Heap
    private var primaryIntermediateTexture: MTLTexture?
    private var secondaryIntermediateTexture: MTLTexture?
    private var transientComputeTexture: MTLTexture?
    private var outputDisplayTexture: MTLTexture?
    
    // Current resolution tracked
    private var currentWidth: Int = 1920
    private var currentHeight: Int = 1080
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    public init?(device: MTLDevice? = nil) {
        guard let mtlDevice = device ?? MTLCreateSystemDefaultDevice(),
              let queue = mtlDevice.makeCommandQueue() else {
            return nil
        }
        self.device = mtlDevice
        self.commandQueue = queue
        
        setupHeap()
        setupThermalAndMemoryObservers()
    }
    
    // MARK: - Heap Lifecycle
    
    private func setupHeap() {
        heapLock.lock()
        defer { heapLock.unlock() }
        
        let descriptor = MTLHeapDescriptor()
        descriptor.size = Self.maxHeapBudgetBytes
        descriptor.storageMode = .private
        descriptor.hazardTrackingMode = .tracked
        descriptor.type = .placement
        
        guard let newHeap = device.makeHeap(descriptor: descriptor) else {
            // Fallback to automatic heap if placement heap is unavailable
            descriptor.type = .automatic
            self.heap = device.makeHeap(descriptor: descriptor)
            return
        }
        self.heap = newHeap
    }
    
    private func setupThermalAndMemoryObservers() {
        NotificationCenter.default.publisher(for: .vlcUltimateVideoPrecisionFallbackRequested)
            .sink { [weak self] notification in
                guard let self = self,
                      let allowHighPrecision = notification.userInfo?["highPrecision"] as? Bool else { return }
                self.setHighPrecisionAllowed(allowHighPrecision)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .vlcUltimatePurgeNonEssentialCachesRequested)
            .sink { [weak self] _ in
                self?.purgeTransientTextures()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Precision Switching
    
    public func setHighPrecisionAllowed(_ allowed: Bool) {
        heapLock.lock()
        defer { heapLock.unlock() }
        
        if self.isHighPrecision == allowed {
            return
        }
        
        self.isHighPrecision = allowed
        self.activePixelFormat = allowed ? .rgba16Float : .bgra8Unorm
        
        // Re-allocate heap textures with new pixel format
        reallocateTexturesFromHeap(width: currentWidth, height: currentHeight)
    }
    
    // MARK: - Zero-Allocation Texture Accessors
    
    /// Pre-allocates or reconfigures textures on resolution change.
    /// Uses MTLHeap texture aliasing: transientComputeTexture shares memory with secondaryIntermediateTexture.
    public func updateResolution(width: Int, height: Int) {
        heapLock.lock()
        defer { heapLock.unlock() }
        
        guard width > 0 && height > 0 else { return }
        if currentWidth == width && currentHeight == height && primaryIntermediateTexture != nil {
            return
        }
        
        self.currentWidth = width
        self.currentHeight = height
        reallocateTexturesFromHeap(width: width, height: height)
    }
    
    private func reallocateTexturesFromHeap(width: Int, height: Int) {
        guard let currentHeap = self.heap else { return }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: self.activePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        
        // Query memory requirements
        let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
        let alignedSize = (sizeAndAlign.size + sizeAndAlign.align - 1) & ~(sizeAndAlign.align - 1)
        
        // 1. Primary Texture at offset 0
        self.primaryIntermediateTexture = currentHeap.makeTexture(descriptor: descriptor, offset: 0)
        
        // 2. Secondary Texture at offset alignedSize
        let secondaryOffset = alignedSize
        if secondaryOffset + alignedSize <= currentHeap.size {
            self.secondaryIntermediateTexture = currentHeap.makeTexture(descriptor: descriptor, offset: secondaryOffset)
        }
        
        // 3. Output Texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        outputDescriptor.storageMode = .private
        let outSizeAlign = device.heapTextureSizeAndAlign(descriptor: outputDescriptor)
        let outAlignedSize = (outSizeAlign.size + outSizeAlign.align - 1) & ~(outSizeAlign.align - 1)
        
        let outputOffset = secondaryOffset + alignedSize
        if outputOffset + outAlignedSize <= currentHeap.size {
            self.outputDisplayTexture = currentHeap.makeTexture(descriptor: outputDescriptor, offset: outputOffset)
        }
        
        // 4. Memory Aliasing: Transient scratch texture aliases secondary texture offset
        // Used in serial multi-pass compute shaders without expanding memory footprint
        if secondaryOffset + alignedSize <= currentHeap.size {
            self.transientComputeTexture = currentHeap.makeTexture(descriptor: descriptor, offset: secondaryOffset)
            self.transientComputeTexture?.makeAliasable()
        }
    }
    
    /// Retrieves primary ping-pong intermediate texture.
    public var primaryTexture: MTLTexture? {
        heapLock.lock()
        defer { heapLock.unlock() }
        return primaryIntermediateTexture
    }
    
    /// Retrieves secondary ping-pong intermediate texture.
    public var secondaryTexture: MTLTexture? {
        heapLock.lock()
        defer { heapLock.unlock() }
        return secondaryIntermediateTexture
    }
    
    /// Retrieves aliasable transient compute scratch texture.
    public var scratchTexture: MTLTexture? {
        heapLock.lock()
        defer { heapLock.unlock() }
        return transientComputeTexture
    }
    
    /// Retrieves output display texture.
    public var outputTexture: MTLTexture? {
        heapLock.lock()
        defer { heapLock.unlock() }
        return outputDisplayTexture
    }
    
    /// Purges volatile resources when memory warnings occur.
    public func purgeTransientTextures() {
        heapLock.lock()
        defer { heapLock.unlock() }
        
        transientComputeTexture?.setPurgeableState(.volatile)
        secondaryIntermediateTexture?.setPurgeableState(.volatile)
    }
    
    /// Returns current heap size in megabytes.
    public var heapUsageMB: Double {
        heapLock.lock()
        defer { heapLock.unlock() }
        guard let heap = self.heap else { return 0.0 }
        return Double(heap.usedSize) / (1024.0 * 1024.0)
    }
}
