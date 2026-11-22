//
//  UltimateAudioMixerUI.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Studio Audio Workstation & 2-Tier Karaoke Pitch Bar View.
//

import SwiftUI

public struct UltimateAudioMixerUI: View {
    @ObservedObject var engine = UltimateAudioEngine.shared
    @State private var selectedTab: Int = 0 // 0: Studio DSP, 1: Karaoke & Pitch
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar & Mode Selector
            headerView
            
            // Tab Selector
            tabSelectorView
            
            // Main Content Area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if selectedTab == 0 {
                        studioDspSection
                    } else {
                        karaokeSection
                    }
                    
                    // Hikaproj Customization Credits
                    hikaprojCreditsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(UltimateDesignSystem.Colors.obsidianBlack.ignoresSafeArea())
    }
    
    // MARK: - Header & Meter
    
    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VLC ULTIMATE AUDIO DSP")
                    .font(UltimateDesignSystem.Typography.dspTitle)
                    .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(UltimateDesignSystem.Colors.neonTeal)
                        .frame(width: 6, height: 6)
                    Text("ACTIVE CHORD:")
                        .font(UltimateDesignSystem.Typography.dialLabel)
                        .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    Text(engine.activeChord)
                        .font(UltimateDesignSystem.Typography.timecode)
                        .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                }
            }
            
            Spacer()
            
            // Compact RMS/Peak Meter
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "PEAK: %.1f dB", engine.currentPeakDb))
                    .font(UltimateDesignSystem.Typography.meterText)
                    .foregroundColor(engine.currentPeakDb > -1.0 ? UltimateDesignSystem.Colors.studioCrimson : UltimateDesignSystem.Colors.textSecondary)
                
                // Meter Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(UltimateDesignSystem.Colors.studioBorder)
                        
                        let norm = max(0.0, min(1.0, (Double(engine.currentPeakDb) + 60.0) / 60.0))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [UltimateDesignSystem.Colors.meterGreen, UltimateDesignSystem.Colors.meterYellow, UltimateDesignSystem.Colors.studioCrimson],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * norm)
                    }
                }
                .frame(width: 80, height: 5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
    
    private var tabSelectorView: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(UltimateDesignSystem.ultimateSpring) { selectedTab = 0 }
                UltimateHapticEngine.shared.playJogTick()
            } label: {
                Text("STUDIO DSP SUITE")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(selectedTab == 0 ? UltimateDesignSystem.Colors.obsidianBlack : UltimateDesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == 0 ? UltimateDesignSystem.Colors.neonTeal : Color.clear)
                    )
            }
            
            Button {
                withAnimation(UltimateDesignSystem.ultimateSpring) { selectedTab = 1 }
                UltimateHapticEngine.shared.playJogTick()
            } label: {
                Text("KARAOKE & PITCH SCORING")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(selectedTab == 1 ? UltimateDesignSystem.Colors.obsidianBlack : UltimateDesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == 1 ? UltimateDesignSystem.Colors.cyberOrange : Color.clear)
                    )
            }
        }
        .padding(4)
        .background(UltimateDesignSystem.Colors.studioSurface)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Tab 1: Studio DSP Suite
    
    private var studioDspSection: some View {
        VStack(spacing: 12) {
            // Sony Walkman Group
            VStack(alignment: .leading, spacing: 12) {
                Text("SONY WALKMAN® SOUND ENGINES")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(UltimateDesignSystem.Colors.electricCyan)
                
                // DSEE Ultimate
                Toggle(isOn: $engine.dseeUltimateEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DSEE Ultimate™ (High-Res Harmonic)")
                            .font(UltimateDesignSystem.Typography.dspTitle)
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        Text("Harmonic waveshaping & 14kHz-22kHz air restore")
                            .font(.caption2)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    }
                }
                .tint(UltimateDesignSystem.Colors.neonTeal)
                .onChange(of: engine.dseeUltimateEnabled) { _ in UltimateHapticEngine.shared.playJogTick() }
                
                if engine.dseeUltimateEnabled {
                    HStack {
                        Text("Blend:")
                            .font(UltimateDesignSystem.Typography.dialLabel)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                        Slider(value: $engine.dseeBlendAmount, in: 0.0...1.0)
                            .tint(UltimateDesignSystem.Colors.neonTeal)
                    }
                }
                
                Divider().background(UltimateDesignSystem.Colors.studioBorder)
                
                // Vinyl Processor
                Toggle(isOn: $engine.vinylProcessorEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vinyl Processor (Tonearm Resonance)")
                            .font(UltimateDesignSystem.Typography.dspTitle)
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        Text("25Hz peaking EQ & even-harmonic tube saturation")
                            .font(.caption2)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    }
                }
                .tint(UltimateDesignSystem.Colors.cyberOrange)
                .onChange(of: engine.vinylProcessorEnabled) { _ in UltimateHapticEngine.shared.playJogTick() }
                
                Divider().background(UltimateDesignSystem.Colors.studioBorder)
                
                // DC Phase Linearizer
                VStack(alignment: .leading, spacing: 6) {
                    Text("DC Phase Linearizer (Class-A Bass Attack)")
                        .font(UltimateDesignSystem.Typography.dspTitle)
                        .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                    
                    Picker("DC Phase", selection: $engine.dcPhaseMode) {
                        Text("Off").tag(DCPhaseLinearizerMode.dcPhaseLinearizer_Off)
                        Text("Standard").tag(DCPhaseLinearizerMode.dcPhaseLinearizer_Standard)
                        Text("Low").tag(DCPhaseLinearizerMode.dcPhaseLinearizer_Low)
                        Text("High").tag(DCPhaseLinearizerMode.dcPhaseLinearizer_High)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: engine.dcPhaseMode) { _ in UltimateHapticEngine.shared.playDetentSnap() }
                }
            }
            .padding(14)
            .ultimateGlassCard()
            
            // Dolby & Utilities Group
            VStack(alignment: .leading, spacing: 12) {
                Text("DOLBY® & DYNAMICS UTILITIES")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(UltimateDesignSystem.Colors.electricCyan)
                
                // 7.1.4ch Spatial Audio
                Toggle(isOn: $engine.spatialAudio714Enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("7.1.4ch Virtual Spatial Audio")
                            .font(UltimateDesignSystem.Typography.dspTitle)
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        Text("Schroeder/Moorer FDN Binaural Immersion")
                            .font(.caption2)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    }
                }
                .tint(UltimateDesignSystem.Colors.neonTeal)
                
                // Dialog Enhancer
                Toggle(isOn: $engine.dialogEnhancerEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dialog Enhancer (Mid/Side Ducking)")
                            .font(UltimateDesignSystem.Typography.dspTitle)
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        Text("1k-4kHz formant detection with -4.5dB side duck")
                            .font(.caption2)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    }
                }
                .tint(UltimateDesignSystem.Colors.electricCyan)
                
                // Night Mode
                Toggle(isOn: $engine.nightModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Night Mode (2ms Lookahead Compressor)")
                            .font(UltimateDesignSystem.Typography.dspTitle)
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        Text("8:1 Peak limiting with automatic makeup gain")
                            .font(.caption2)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    }
                }
                .tint(UltimateDesignSystem.Colors.meterYellow)
            }
            .padding(14)
            .ultimateGlassCard()
        }
    }
    
    // MARK: - Tab 2: Karaoke & 2-Tier Pitch Scoring
    
    private var karaokeSection: some View {
        VStack(spacing: 14) {
            // 2-Tier Real-Time Scrolling Pitch Bar (Piano Roll)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("REAL-TIME 2-TIER PITCH BAR")
                        .font(UltimateDesignSystem.Typography.dialLabel)
                        .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                    Spacer()
                    Text(String(format: "SCORE: %.1f %%", engine.karaokeScore))
                        .font(UltimateDesignSystem.Typography.timecode)
                        .foregroundColor(UltimateDesignSystem.Colors.cyberOrange)
                }
                
                // Piano Roll Canvas
                Canvas { context, size in
                    // Grid background
                    let w = size.width
                    let h = size.height
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(UltimateDesignSystem.Colors.studioSurface))
                    
                    let points = engine.pitchHistory
                    guard points.count > 1 else { return }
                    
                    // Note range C3 (48) to C6 (84) = 36 semitones
                    let minMidi: Float = 48.0
                    let maxMidi: Float = 84.0
                    let midiRange = maxMidi - minMidi
                    
                    // Draw Accompaniment Target Notes (Neon Cyan)
                    for (i, p) in points.enumerated() {
                        let x = CGFloat(i) / CGFloat(points.count) * w
                        if p.accompanimentMidi >= minMidi && p.accompanimentMidi <= maxMidi {
                            let y = h - CGFloat((p.accompanimentMidi - minMidi) / midiRange) * h
                            let rect = CGRect(x: x - 4, y: y - 3, width: 8, height: 6)
                            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(UltimateDesignSystem.Colors.neonTeal.opacity(0.85)))
                        }
                    }
                    
                    // Draw Singer Microphone Pitch (Gold/Cyber Orange with Glow)
                    for (i, p) in points.enumerated() {
                        let x = CGFloat(i) / CGFloat(points.count) * w
                        if p.vocalMidi >= minMidi && p.vocalMidi <= maxMidi {
                            let y = h - CGFloat((p.vocalMidi - minMidi) / midiRange) * h
                            let hitColor = p.isHit ? UltimateDesignSystem.Colors.meterGreen : UltimateDesignSystem.Colors.cyberOrange
                            let rect = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
                            context.fill(Path(ellipseIn: rect), with: .color(hitColor))
                        }
                    }
                }
                .frame(height: 120)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UltimateDesignSystem.Colors.studioBorder, lineWidth: 1))
            }
            .padding(14)
            .ultimateGlassCard()
            
            // Vocal Controls & Key Change
            VStack(alignment: .leading, spacing: 12) {
                Text("VOCAL PROCESSING & KEY SHIFT")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(UltimateDesignSystem.Colors.cyberOrange)
                
                // Vocal Remover
                Toggle("Center-Channel Vocal Remover (Mono Bass Preserved)", isOn: $engine.vocalRemoverEnabled)
                    .font(UltimateDesignSystem.Typography.dspTitle)
                    .tint(UltimateDesignSystem.Colors.cyberOrange)
                
                // Key Shift (-6 to +6 Semitones)
                HStack {
                    Text("Key Shift:")
                        .font(UltimateDesignSystem.Typography.dialLabel)
                        .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    
                    Button {
                        if engine.keyShiftSemitones > -6 {
                            engine.keyShiftSemitones -= 1
                            UltimateHapticEngine.shared.playJogTick()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title3)
                    }
                    .tint(UltimateDesignSystem.Colors.electricCyan)
                    
                    Text(String(format: "%+d st", engine.keyShiftSemitones))
                        .font(UltimateDesignSystem.Typography.timecode)
                        .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        .frame(width: 60)
                    
                    Button {
                        if engine.keyShiftSemitones < 6 {
                            engine.keyShiftSemitones += 1
                            UltimateHapticEngine.shared.playJogTick()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .tint(UltimateDesignSystem.Colors.electricCyan)
                    
                    Spacer()
                    
                    Button("RESET") {
                        engine.keyShiftSemitones = 0
                        UltimateHapticEngine.shared.playDetentSnap()
                    }
                    .font(.caption2.bold())
                    .tint(UltimateDesignSystem.Colors.studioCrimson)
                }
                
                Divider().background(UltimateDesignSystem.Colors.studioBorder)
                
                // Mic Monitoring Toggle
                Toggle(isOn: $engine.isMicMonitoringActive) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Mic Monitoring (5.33ms Ultra-Low Latency)")
                            .font(UltimateDesignSystem.Typography.dspTitle)
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        Text("AVAudioSession hardware echo cancellation")
                            .font(.caption2)
                            .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
                    }
                }
                .tint(UltimateDesignSystem.Colors.neonTeal)
                .onChange(of: engine.isMicMonitoringActive) { active in
                    if active {
                        engine.startMicMonitoring()
                    } else {
                        engine.stopMicMonitoring()
                    }
                    UltimateHapticEngine.shared.playDetentSnap()
                }
                
                // Auto-Tune & Multi-Harmony
                Toggle("Real-Time Pitch Auto-Tune", isOn: $engine.autoTuneEnabled)
                    .font(UltimateDesignSystem.Typography.dspTitle)
                    .tint(UltimateDesignSystem.Colors.meterGreen)
                
                Toggle("Chord-Synced Auto Harmonies (+3rd, -3rd, -8ve)", isOn: $engine.harmonyEnabled)
                    .font(UltimateDesignSystem.Typography.dspTitle)
                    .tint(UltimateDesignSystem.Colors.neonTeal)
            }
            .padding(14)
            .ultimateGlassCard()
        }
    }
    
    // MARK: - Hikaproj Customization Credits
    
    private var hikaprojCreditsSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                Text("CUSTOMIZED BY HIKAPROJ")
                    .font(UltimateDesignSystem.Typography.dialLabel)
                    .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
            }
            
            Text("VLC Ultimate Media & Audio Workstation Edition")
                .font(.caption2)
                .foregroundColor(UltimateDesignSystem.Colors.textSecondary)
            
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://x.com/hikaproj")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "at")
                        Text("@hikaproj")
                    }
                    .font(.caption.bold())
                    .foregroundColor(UltimateDesignSystem.Colors.electricCyan)
                }
                
                Link(destination: URL(string: "https://hikaproj.com")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("hikaproj.com")
                    }
                    .font(.caption.bold())
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                }
                
                Link(destination: URL(string: "https://hikaproj.com/new/contact")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                        Text("Contact")
                    }
                    .font(.caption.bold())
                    .foregroundColor(UltimateDesignSystem.Colors.cyberOrange)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .ultimateGlassCard()
    }
}
