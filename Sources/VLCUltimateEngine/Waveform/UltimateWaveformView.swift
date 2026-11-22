//
//  UltimateWaveformView.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Interactive 60fps Waveform Seekbar, Highlight Heatmap, AB Loop Drag, and Silence Auto-Skip.
//

import SwiftUI

public struct UltimateWaveformView: View {
    public let waveformPoints: [WaveformPoint]
    public let silenceIntervals: [SilenceInterval]
    public let duration: TimeInterval
    
    @Binding public var currentTime: TimeInterval
    @Binding public var loopStart: TimeInterval?
    @Binding public var loopEnd: TimeInterval?
    @Binding public var autoSkipSilenceEnabled: Bool
    
    @State private var isDraggingScrubber = false
    @State private var draggingPoint: Int? = nil // 1: Point A, 2: Point B
    @State private var memoInputText = ""
    @State private var showMemoSheet = false
    
    public init(
        waveformPoints: [WaveformPoint],
        silenceIntervals: [SilenceInterval] = [],
        duration: TimeInterval,
        currentTime: Binding<TimeInterval>,
        loopStart: Binding<TimeInterval?>,
        loopEnd: Binding<TimeInterval?>,
        autoSkipSilenceEnabled: Binding<Bool>
    ) {
        self.waveformPoints = waveformPoints
        self.silenceIntervals = silenceIntervals
        self.duration = duration
        self._currentTime = currentTime
        self._loopStart = loopStart
        self._loopEnd = loopEnd
        self._autoSkipSilenceEnabled = autoSkipSilenceEnabled
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Top Status & Timing Row
            HStack {
                Text(formatTime(currentTime))
                    .font(UltimateDesignSystem.Typography.timecode)
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                
                Spacer()
                
                // Silence Auto-Skip Indicator
                if autoSkipSilenceEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.fill")
                            .font(.caption2)
                        Text("AUTO-SKIP SILENCE (2.5x)")
                            .font(UltimateDesignSystem.Typography.dialLabel)
                    }
                    .foregroundColor(UltimateDesignSystem.Colors.meterYellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(UltimateDesignSystem.Colors.studioSurface)
                    .cornerRadius(4)
                }
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(UltimateDesignSystem.Typography.timecode)
                    .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
            }
            
            // Interactive Waveform Canvas
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                
                ZStack(alignment: .leading) {
                    // 1. Waveform Canvas
                    Canvas { context, size in
                        guard waveformPoints.count > 0 else { return }
                        let barCount = waveformPoints.count
                        let barWidth = max(1.5, size.width / CGFloat(barCount))
                        let midY = size.height * 0.5
                        
                        // Draw silence zones first
                        for interval in silenceIntervals {
                            let startX = CGFloat(interval.startTime / duration) * size.width
                            let endX = CGFloat(interval.endTime / duration) * size.width
                            let rect = CGRect(x: startX, y: 0, width: max(2, endX - startX), height: size.height)
                            context.fill(Path(rect), with: .color(Color.gray.opacity(0.18)))
                        }
                        
                        // Draw Waveform Bars with Highlight Heatmap Colors
                        for (i, p) in waveformPoints.enumerated() {
                            let x = CGFloat(i) * barWidth
                            let peakH = CGFloat(p.peak) * midY * 0.95
                            let rmsH = CGFloat(p.rms) * midY * 0.85
                            
                            // Highlight Color Gradient: Cold Teal (0.0) -> Neon Cyan (0.3) -> Amber (0.7) -> Cyber Orange (1.0)
                            let barColor = colorForHighlightScore(p.highlightScore)
                            
                            // Peak thin line
                            let peakRect = CGRect(x: x, y: midY - peakH, width: barWidth * 0.75, height: peakH * 2.0)
                            context.fill(Path(roundedRect: peakRect, cornerRadius: 1), with: .color(barColor.opacity(0.40)))
                            
                            // RMS thick core
                            let rmsRect = CGRect(x: x, y: midY - rmsH, width: barWidth * 0.85, height: rmsH * 2.0)
                            context.fill(Path(roundedRect: rmsRect, cornerRadius: 1), with: .color(barColor))
                        }
                    }
                    
                    // 2. AB Loop Section Overlay
                    if let a = loopStart, let b = loopEnd {
                        let startX = CGFloat(a / duration) * width
                        let endX = CGFloat(b / duration) * width
                        Rectangle()
                            .fill(UltimateDesignSystem.Colors.neonTeal.opacity(0.22))
                            .frame(width: max(0, endX - startX), height: height)
                            .offset(x: startX)
                            .overlay(
                                Rectangle()
                                    .stroke(UltimateDesignSystem.Colors.neonTeal, lineWidth: 1.5)
                                    .frame(width: max(0, endX - startX), height: height)
                                    .offset(x: startX)
                            )
                    }
                    
                    // 3. Current Playhead Needle
                    let playheadX = duration > 0 ? CGFloat(currentTime / duration) * width : 0
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2.0, height: height + 8)
                        .offset(x: playheadX - 1.0, y: -4)
                        .shadow(color: UltimateDesignSystem.Colors.neonTeal, radius: 4)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0.0, min(1.0, Double(value.location.x / width)))
                            self.currentTime = fraction * duration
                            UltimateHapticEngine.shared.playJogTick(intensity: 0.3)
                        }
                )
            }
            .frame(height: 58)
            .padding(10)
            .ultimateGlassCard()
            
            // Bottom Action Controls (AB Repeat & Silence Toggle)
            HStack(spacing: 12) {
                Button {
                    if loopStart == nil {
                        loopStart = currentTime
                    } else if loopEnd == nil {
                        loopEnd = currentTime
                    } else {
                        loopStart = nil
                        loopEnd = nil
                    }
                    UltimateHapticEngine.shared.playDetentSnap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                        if let a = loopStart, let b = loopEnd {
                            Text("LOOP A-B (\(formatTime(a))-\(formatTime(b)))")
                        } else if loopStart != nil {
                            Text("SET B POINT")
                        } else {
                            Text("SET A-B REPEAT")
                        }
                    }
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(loopStart != nil ? UltimateDesignSystem.Colors.neonTeal : UltimateDesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                Toggle("Auto-Skip Silence", isOn: $autoSkipSilenceEnabled)
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    .tint(UltimateDesignSystem.Colors.meterYellow)
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func colorForHighlightScore(_ score: Float) -> Color {
        if score > 0.75 {
            return UltimateDesignSystem.Colors.cyberOrange
        } else if score > 0.45 {
            return UltimateDesignSystem.Colors.meterYellow
        } else if score > 0.20 {
            return UltimateDesignSystem.Colors.neonTeal
        } else {
            return UltimateDesignSystem.Colors.electricCyan
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1.0)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, millis)
    }
}
