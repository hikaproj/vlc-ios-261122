//
//  UltimateVideoPlayerView.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Metal Video Surface with 2-Screen Wipe Comparison, Pinch Loupe, Minimap, and Studio Controls.
//

import SwiftUI
import MetalKit

// MARK: - Metal MTKView Coordinator

public struct UltimateMetalVideoSurface: UIViewRepresentable {
    @ObservedObject var pipeline = UltimateVideoPipeline.shared
    
    public init() {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(pipeline: pipeline)
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = pipeline.device
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60
        context.coordinator.mtkView = mtkView
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        // Dynamic properties updated reactively
    }
    
    public final class Coordinator: NSObject, MTKViewDelegate {
        let pipeline: UltimateVideoPipeline
        weak var mtkView: MTKView?
        var activePixelBuffer: CVPixelBuffer?
        var secondaryPixelBuffer: CVPixelBuffer?
        
        init(pipeline: UltimateVideoPipeline) {
            self.pipeline = pipeline
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        public func draw(in view: MTKView) {
            guard let pixelBuffer = activePixelBuffer,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable else { return }
            
            pipeline.processFrame(
                pixelBuffer: pixelBuffer,
                secondaryPixelBuffer: secondaryPixelBuffer,
                renderPassDescriptor: renderPassDescriptor
            )
            
            if let commandBuffer = pipeline.commandQueue.makeCommandBuffer() {
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
        }
    }
}

// MARK: - Full Interactive Video Player View

public struct UltimateVideoPlayerView: View {
    @ObservedObject var pipeline = UltimateVideoPipeline.shared
    @State private var showControlsDrawer = false
    @State private var wipeSliderValue: Float = 1.0
    @State private var loupeScale: CGFloat = 3.0
    @State private var lastLoupeScale: CGFloat = 3.0
    @State private var loupeDragOffset = CGSize.zero
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 1. Metal Video View Surface
            UltimateMetalVideoSurface()
                .ignoresSafeArea()
            
            // 2. Gesture Overlay for Loupe
            loupeGestureLayer
            
            // 3. Minimap Overlay (when Loupe or Zoom is active)
            if pipeline.isLoupeActive {
                minimapOverlay
            }
            
            // 4. Wipe Comparison Slider Bar (Bottom overlay)
            VStack {
                Spacer()
                wipeControlBar
            }
            .padding(.bottom, 24)
            
            // 5. Studio Controls Drawer
            if showControlsDrawer {
                controlsDrawerOverlay
            }
        }
    }
    
    // MARK: - Gestures Layer for Circular Loupe
    
    private var loupeGestureLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = Float(value)
                            let newZoom = max(1.0, min(10.0, Float(lastLoupeScale) * delta))
                            pipeline.isLoupeActive = true
                            pipeline.loupeZoom = newZoom
                        }
                        .onEnded { value in
                            lastLoupeScale = CGFloat(pipeline.loupeZoom)
                            UltimateHapticEngine.shared.playDetentSnap()
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let uvX = max(0.0, min(1.0, value.location.x / geo.size.width))
                            let uvY = max(0.0, min(1.0, value.location.y / geo.size.height))
                            pipeline.loupeCenter = CGPoint(x: uvX, y: uvY)
                        }
                )
        }
    }
    
    // MARK: - Bottom Minimap Overlay
    
    private var minimapOverlay: some View {
        VStack {
            HStack {
                Spacer()
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 120, height: 68)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(UltimateDesignSystem.Colors.studioBorder, lineWidth: 1))
                    
                    // Zoom viewport indicator rectangle
                    let boxW: CGFloat = 120.0 / CGFloat(pipeline.loupeZoom)
                    let boxH: CGFloat = 68.0 / CGFloat(pipeline.loupeZoom)
                    let boxX = (CGFloat(pipeline.loupeCenter.x) * 120.0) - boxW / 2
                    let boxY = (CGFloat(pipeline.loupeCenter.y) * 68.0) - boxH / 2
                    
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(UltimateDesignSystem.Colors.neonTeal, lineWidth: 1.5)
                        .frame(width: boxW, height: boxH)
                        .offset(x: max(0, min(120 - boxW, boxX)), y: max(0, min(68 - boxH, boxY)))
                }
                .padding(.trailing, 16)
                .padding(.top, 40)
            }
            Spacer()
        }
    }
    
    // MARK: - 2-Screen Wipe Control Bar
    
    private var wipeControlBar: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(UltimateDesignSystem.ultimateSpring) {
                    showControlsDrawer.toggle()
                }
                UltimateHapticEngine.shared.playJogTick()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                    .font(.headline)
                    .padding(10)
                    .background(Circle().fill(UltimateDesignSystem.Colors.studioSurface))
            }
            
            // Wipe Split Slider
            HStack(spacing: 8) {
                Text("ORIG")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                
                Slider(value: $pipeline.wipeSplitX, in: 0.0...1.0)
                    .tint(UltimateDesignSystem.Colors.neonTeal)
                    .onChange(of: pipeline.wipeSplitX) { val in
                        if abs(val - 0.50) < 0.02 {
                            pipeline.wipeSplitX = 0.50
                            UltimateHapticEngine.shared.playDetentSnap()
                        } else {
                            UltimateHapticEngine.shared.playJogTick(intensity: 0.25)
                        }
                    }
                
                Text("STUDIO")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .ultimateGlassCard()
            
            // Loupe Toggle
            Button {
                withAnimation(UltimateDesignSystem.snapSpring) {
                    pipeline.isLoupeActive.toggle()
                }
                UltimateHapticEngine.shared.playDetentSnap()
            } label: {
                Image(systemName: pipeline.isLoupeActive ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                    .foregroundColor(pipeline.isLoupeActive ? UltimateDesignSystem.Colors.cyberOrange : UltimateDesignSystem.Colors.textSecondary)
                    .font(.title2)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Studio Controls Drawer Overlay
    
    private var controlsDrawerOverlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("METAL VIDEO PROCESSING PIPELINE")
                        .font(UltimateDesignSystem.Typography.dspTitle)
                        .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                    Spacer()
                    Button {
                        withAnimation(UltimateDesignSystem.ultimateSpring) { showControlsDrawer = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    }
                }
                
                // HDR Tone Mapping
                Toggle("Dolby Dynamic HDR Tone Mapping (ACES)", isOn: $pipeline.hdrToneMappingEnabled)
                    .tint(UltimateDesignSystem.Colors.neonTeal)
                    .font(UltimateDesignSystem.Typography.dialLabel)
                
                // Anime4K CAS Sharpening
                Toggle("Anime4K Edge Thinning & CAS Sharpening", isOn: $pipeline.anime4kSharpenEnabled)
                    .tint(UltimateDesignSystem.Colors.neonTeal)
                    .font(UltimateDesignSystem.Typography.dialLabel)
                
                if pipeline.anime4kSharpenEnabled {
                    HStack {
                        Text("Sharpness:")
                            .font(.caption2)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                        Slider(value: $pipeline.casSharpness, in: 0.0...1.0)
                            .tint(UltimateDesignSystem.Colors.neonTeal)
                    }
                }
                
                // Retro CRT
                Toggle("Retro CRT Display (Scanlines & Phosphor)", isOn: $pipeline.retroCrtEnabled)
                    .tint(UltimateDesignSystem.Colors.cyberOrange)
                    .font(UltimateDesignSystem.Typography.dialLabel)
                
                // Stabilization & Deinterlace
                HStack(spacing: 12) {
                    Toggle("Stabilize", isOn: $pipeline.stabilizationEnabled)
                        .tint(UltimateDesignSystem.Colors.meterGreen)
                        .font(.caption2.bold())
                    
                    Toggle("Deinterlace", isOn: $pipeline.deinterlaceEnabled)
                        .tint(UltimateDesignSystem.Colors.electricCyan)
                        .font(.caption2.bold())
                    
                    Toggle("Auto-Crop", isOn: $pipeline.autoCropBlackBarsEnabled)
                        .tint(UltimateDesignSystem.Colors.meterYellow)
                        .font(.caption2.bold())
                }
            }
            .padding(18)
            .ultimateGlassCard()
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
