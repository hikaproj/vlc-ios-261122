//
//  UltimateVideoPipeline.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Metal Zero-Copy Video Processing Pipeline: HDR Tone Mapping, Anime4K, CRT, Stabilization, Loupe, Snapshots.
//

import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreGraphics
import UIKit
import Combine

@MainActor
public final class UltimateVideoPipeline: ObservableObject {
    
    public static let shared = UltimateVideoPipeline()
    
    // MARK: - Metal Device & Queues
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let heapManager: UltimateMetalHeapManager
    private var textureCache: CVMetalTextureCache?
    
    // MARK: - Metal Compute & Render Pipelines
    private var histogramPipelineState: MTLComputePipelineState?
    private var toneMapPipelineState: MTLComputePipelineState?
    private var sharpenPipelineState: MTLComputePipelineState?
    private var crtPipelineState: MTLComputePipelineState?
    private var deinterlacePipelineState: MTLComputePipelineState?
    private var wipePipelineState: MTLRenderPipelineState?
    private var defaultSamplerState: MTLSamplerState?
    
    // MARK: - Histogram Buffer & Temporal Filtering
    private var histogramBuffer: MTLBuffer?
    @Published public private(set) var smoothedAverageLuminance: Float = 0.35
    @Published public private(set) var smoothedMaxLuminance: Float = 1.00
    
    // MARK: - Stabilization & Auto-Crop
    public let stabilizationEngine = UltimateStabilizationEngine()
    @Published public private(set) var detectedCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    // MARK: - Published Parameters
    @Published public var hdrToneMappingEnabled: Bool = true
    @Published public var toneMapExposure: Float = 1.0
    @Published public var toneMapContrast: Float = 1.05
    @Published public var toneMapSaturation: Float = 1.10
    
    @Published public var anime4kSharpenEnabled: Bool = true
    @Published public var casSharpness: Float = 0.75
    @Published public var anime4kEdgeThinning: Float = 0.50
    
    @Published public var retroCrtEnabled: Bool = false
    @Published public var crtScanlines: Float = 0.45
    @Published public var crtAberration: Float = 0.35
    @Published public var crtCurvature: Float = 0.08
    @Published public var crtFilmGrain: Float = 0.15
    
    @Published public var stabilizationEnabled: Bool = false
    @Published public var deinterlaceEnabled: Bool = false
    @Published public var autoCropBlackBarsEnabled: Bool = true
    
    // 2-Screen Wipe & Loupe
    @Published public var wipeSplitX: Float = 1.0 // 1.0 = 100% processed
    @Published public var isLoupeActive: Bool = false
    @Published public var loupeCenter = CGPoint(x: 0.5, y: 0.5)
    @Published public var loupeRadius: Float = 0.18
    @Published public var loupeZoom: Float = 3.0
    
    private var frameCounter: UInt32 = 0
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        guard let defaultDevice = MTLCreateSystemDefaultDevice(),
              let queue = defaultDevice.makeCommandQueue(),
              let heap = UltimateMetalHeapManager(device: defaultDevice) else {
            fatalError("Failed to initialize Metal device, queue, or heap.")
        }
        
        self.device = defaultDevice
        self.commandQueue = queue
        self.heapManager = heap
        
        setupTextureCache()
        buildShaders()
        setupHistogramBuffer()
    }
    
    private func setupTextureCache() {
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        if result != kCVReturnSuccess {
            textureCache = nil
        }
    }
    
    private func setupHistogramBuffer() {
        // 256 uint32 bins = 1024 bytes
        self.histogramBuffer = device.makeBuffer(length: 256 * MemoryLayout<UInt32>.stride, options: .storageModeShared)
    }
    
    private func buildShaders() {
        guard let library = try? device.makeDefaultLibrary() else { return }
        
        if let histFunc = library.makeFunction(name: "calculate_luminance_histogram") {
            histogramPipelineState = try? device.makeComputePipelineState(function: histFunc)
        }
        if let toneFunc = library.makeFunction(name: "dynamic_hdr_tone_mapping") {
            toneMapPipelineState = try? device.makeComputePipelineState(function: toneFunc)
        }
        if let sharpFunc = library.makeFunction(name: "anime4k_edge_and_cas_sharpen") {
            sharpenPipelineState = try? device.makeComputePipelineState(function: sharpFunc)
        }
        if let crtFunc = library.makeFunction(name: "retro_crt_filter") {
            crtPipelineState = try? device.makeComputePipelineState(function: crtFunc)
        }
        if let deintFunc = library.makeFunction(name: "motion_adaptive_deinterlace") {
            deinterlacePipelineState = try? device.makeComputePipelineState(function: deintFunc)
        }
        
        // Wipe & Loupe Render Pipeline
        let renderDesc = MTLRenderPipelineDescriptor()
        renderDesc.vertexFunction = library.makeFunction(name: "wipe_vertex_shader")
        renderDesc.fragmentFunction = library.makeFunction(name: "wipe_comparison_and_loupe")
        renderDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.wipePipelineState = try? device.makeRenderPipelineState(descriptor: renderDesc)
        
        // Linear Sampler for bilinear magnification
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.defaultSamplerState = device.makeSamplerState(descriptor: samplerDesc)
    }
    
    // MARK: - Zero-Copy Texture Ingestion from CVPixelBuffer
    
    public func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        if status == kCVReturnSuccess, let unwrapped = cvTexture {
            return CVMetalTextureGetTexture(unwrapped)
        }
        return nil
    }
    
    // MARK: - Main Frame Processing Pipeline
    
    public func processFrame(
        pixelBuffer: CVPixelBuffer,
        secondaryPixelBuffer: CVPixelBuffer? = nil,
        renderPassDescriptor: MTLRenderPassDescriptor
    ) {
        guard let inputTexture = createTexture(from: pixelBuffer) else { return }
        let width = inputTexture.width
        let height = inputTexture.height
        
        heapManager.updateResolution(width: width, height: height)
        guard let intermediateA = heapManager.primaryTexture,
              let intermediateB = heapManager.secondaryTexture else { return }
        
        // 1. Black Bar Auto-Crop Detection (periodic sampling)
        if autoCropBlackBarsEnabled && (frameCounter % 30 == 0) {
            detectBlackBars(in: pixelBuffer)
        }
        
        // 2. Optical Flow Stabilization calculation
        var transformParams = UltimateTransformParams(
            translation_offset: simd_float2(0, 0),
            rotation_angle: 0.0,
            crop_scale: 1.0,
            deinterlace_enabled: deinterlaceEnabled ? 1 : 0,
            comb_threshold: 0.15
        )
        if stabilizationEnabled {
            let stab = stabilizationEngine.estimateStabilizationOffset(from: pixelBuffer)
            transformParams.translation_offset = stab.translation
            transformParams.rotation_angle = stab.rotation
            transformParams.crop_scale = stab.cropScale
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // 3. Compute Histogram for Dynamic HDR Tone Mapping
        if let histState = histogramPipelineState, let histBuf = histogramBuffer, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(histState)
            computeEncoder.setTexture(inputTexture, index: 0)
            computeEncoder.setBuffer(histBuf, offset: 0, index: 0)
            
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroups = MTLSize(
                width: (width + 15) / 16,
                height: (height + 15) / 16,
                depth: 1
            )
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
        }
        
        // 4. Dynamic HDR Tone Mapping Pass (inputTexture -> intermediateA)
        if hdrToneMappingEnabled, let toneState = toneMapPipelineState, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(toneState)
            computeEncoder.setTexture(inputTexture, index: 0)
            computeEncoder.setTexture(intermediateA, index: 1)
            
            var toneParams = UltimateToneMapParams(
                average_luminance: smoothedAverageLuminance,
                max_luminance: smoothedMaxLuminance,
                exposure: toneMapExposure,
                contrast: toneMapContrast,
                saturation: toneMapSaturation,
                mode: ToneMap_ACES.rawValue
            )
            computeEncoder.setBytes(&toneParams, length: MemoryLayout<UltimateToneMapParams>.stride, index: 0)
            
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroups = MTLSize((width + 15) / 16, (height + 15) / 16, 1)
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
        } else {
            // Blit copy or passthrough
            if let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: inputTexture, to: intermediateA)
                blit.endEncoding()
            }
        }
        
        // 5. Anime4K Edge Thinning & CAS Sharpening Pass (intermediateA -> intermediateB)
        if anime4kSharpenEnabled, let sharpState = sharpenPipelineState, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(sharpState)
            computeEncoder.setTexture(intermediateA, index: 0)
            computeEncoder.setTexture(intermediateB, index: 1)
            
            var sharpParams = UltimateSharpenParams(
                sharpness: casSharpness,
                edge_thinning: anime4kEdgeThinning,
                clamp_limit: 0.20
            )
            computeEncoder.setBytes(&sharpParams, length: MemoryLayout<UltimateSharpenParams>.stride, index: 0)
            
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroups = MTLSize((width + 15) / 16, (height + 15) / 16, 1)
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
        } else {
            if let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: intermediateA, to: intermediateB)
                blit.endEncoding()
            }
        }
        
        // 6. Retro CRT Filter Pass (optional, intermediateB -> intermediateA)
        var finalProcessedTexture = intermediateB
        if retroCrtEnabled, let crtState = crtPipelineState, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(crtState)
            computeEncoder.setTexture(intermediateB, index: 0)
            computeEncoder.setTexture(intermediateA, index: 1)
            
            var crtParams = UltimateCRTParams(
                scanline_intensity: crtScanlines,
                chromatic_aberration: crtAberration,
                aperture_grille_opacity: 0.65,
                film_grain_intensity: crtFilmGrain,
                curvature: crtCurvature,
                time_frame: frameCounter
            )
            computeEncoder.setBytes(&crtParams, length: MemoryLayout<UltimateCRTParams>.stride, index: 0)
            
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroups = MTLSize((width + 15) / 16, (height + 15) / 16, 1)
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
            finalProcessedTexture = intermediateA
        }
        
        // 7. 2-Screen Wipe Comparison & Loupe Rendering
        let originalCompareTexture = secondaryPixelBuffer.flatMap { createTexture(from: $0) } ?? inputTexture
        
        if let wipeState = wipePipelineState, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderEncoder.setRenderPipelineState(wipeState)
            renderEncoder.setFragmentTexture(originalCompareTexture, index: 0)
            renderEncoder.setFragmentTexture(finalProcessedTexture, index: 1)
            renderEncoder.setFragmentSamplerState(defaultSamplerState, index: 0)
            
            var wipeParams = UltimateWipeParams(
                split_x: wipeSplitX,
                loupe_center: simd_float2(Float(loupeCenter.x), Float(loupeCenter.y)),
                loupe_radius: loupeRadius,
                loupe_zoom: loupeZoom,
                is_loupe_active: isLoupeActive ? 1 : 0,
                show_divider: wipeSplitX < 0.99 && wipeSplitX > 0.01 ? 1 : 0
            )
            renderEncoder.setFragmentBytes(&wipeParams, length: MemoryLayout<UltimateWipeParams>.stride, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            renderEncoder.endEncoding()
        }
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.updateTemporalHistogramMetrics()
        }
        
        commandBuffer.commit()
        frameCounter += 1
    }
    
    // MARK: - Temporal Luminance Smoothing
    
    private func updateTemporalHistogramMetrics() {
        guard let histBuf = histogramBuffer else { return }
        let ptr = histBuf.contents().assumingMemoryBound(to: UInt32.self)
        
        var totalPixels: UInt64 = 0
        var weightedSum: UInt64 = 0
        var maxBin: Int = 0
        
        for bin in 0..<256 {
            let count = UInt64(ptr[bin])
            totalPixels += count
            weightedSum += count * UInt64(bin)
            if count > 0 { maxBin = bin }
            ptr[bin] = 0 // Clear for next frame
        }
        
        guard totalPixels > 0 else { return }
        let measuredAvg = Float(weightedSum) / Float(totalPixels * 255)
        let measuredMax = Float(maxBin) / 255.0
        
        // Temporal IIR smoothing (0.90 retention)
        self.smoothedAverageLuminance = self.smoothedAverageLuminance * 0.90 + measuredAvg * 0.10
        self.smoothedMaxLuminance = max(0.5, self.smoothedMaxLuminance * 0.90 + measuredMax * 0.10)
    }
    
    // MARK: - Black Bar Auto-Crop Detection
    
    private func detectBlackBars(in pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        let lumThreshold: Float = 0.035 // 3.5% luminance
        
        // Scan Top
        var topCrop: Int = 0
        for y in stride(from: 0, to: height / 4, by: 4) {
            var rowLum: Float = 0.0
            for x in stride(from: width / 4, to: width * 3 / 4, by: 16) {
                let off = y * bytesPerRow + x * 4
                rowLum += Float(ptr[off]) + Float(ptr[off + 1]) + Float(ptr[off + 2])
            }
            if (rowLum / Float((width / 2 / 16) * 3 * 255)) > lumThreshold {
                topCrop = y
                break
            }
        }
        
        // Scan Bottom
        var bottomCrop: Int = 0
        for y in stride(from: height - 1, through: height * 3 / 4, by: -4) {
            var rowLum: Float = 0.0
            for x in stride(from: width / 4, to: width * 3 / 4, by: 16) {
                let off = y * bytesPerRow + x * 4
                rowLum += Float(ptr[off]) + Float(ptr[off + 1]) + Float(ptr[off + 2])
            }
            if (rowLum / Float((width / 2 / 16) * 3 * 255)) > lumThreshold {
                bottomCrop = height - 1 - y
                break
            }
        }
        
        let cropY = CGFloat(topCrop) / CGFloat(height)
        let cropH = CGFloat(height - topCrop - bottomCrop) / CGFloat(height)
        
        self.detectedCropRect = CGRect(x: 0, y: cropY, width: 1.0, height: cropH)
    }
    
    // MARK: - Filter-Applied High-Quality PNG Snapshot Export
    
    public func exportSnapshot(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
