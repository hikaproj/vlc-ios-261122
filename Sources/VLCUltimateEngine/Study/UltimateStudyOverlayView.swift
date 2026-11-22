//
//  UltimateStudyOverlayView.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Bilingual Interactive Subtitle View, Word Dictionary Tokens, OCR Overlay, and FTS5 Subtitle Search.
//

import SwiftUI

public struct UltimateStudyOverlayView: View {
    public let activeCue: SubtitleCue?
    public let onSeekToTime: (TimeInterval) -> Void
    public let onPausePlayback: () -> Void
    
    @ObservedObject var trainer = UltimateShadowingAndSpeedTrainer.shared
    @State private var ocrItems: [OCRTextItem] = []
    @State private var isOCROverlayActive = false
    @State private var searchQuery = ""
    @State private var searchResults: [AnnotationResult] = []
    @State private var showSearchSheet = false
    
    public init(
        activeCue: SubtitleCue?,
        onSeekToTime: @escaping (TimeInterval) -> Void,
        onPausePlayback: @escaping () -> Void
    ) {
        self.activeCue = activeCue
        self.onSeekToTime = onSeekToTime
        self.onPausePlayback = onPausePlayback
    }
    
    public var body: some View {
        ZStack {
            // 1. OCR Interactive Bounding Boxes Overlay (if triggered)
            if isOCROverlayActive {
                ocrBoundingBoxesLayer
            }
            
            // 2. Bilingual Subtitle Display Bar
            VStack {
                Spacer()
                if let cue = activeCue {
                    bilingualSubtitleBar(cue: cue)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 80)
                }
            }
            
            // 3. Top Study Tools Toolbar (OCR Button & FTS5 Search Button)
            VStack {
                HStack(spacing: 12) {
                    // OCR Screen Scanner Button
                    Button {
                        isOCROverlayActive.toggle()
                        onPausePlayback()
                        UltimateHapticEngine.shared.playJogTick()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.viewfinder")
                            Text("OCR SCAN")
                        }
                        .font(UltimateDesignSystem.Typography.dialLabel)
                        .foregroundColor(isOCROverlayActive ? UltimateDesignSystem.Colors.obsidianBlack : UltimateDesignSystem.Colors.neonTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isOCROverlayActive ? UltimateDesignSystem.Colors.neonTeal : UltimateDesignSystem.Colors.studioSurface)
                        )
                    }
                    
                    // Subtitle & Memo FTS5 Search Button
                    Button {
                        showSearchSheet = true
                        UltimateHapticEngine.shared.playJogTick()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                            Text("FTS5 SEARCH")
                        }
                        .font(UltimateDesignSystem.Typography.dialLabel)
                        .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(UltimateDesignSystem.Colors.studioSurface)
                        )
                    }
                    
                    Spacer()
                    
                    // Shadowing Mode Status Tag
                    if trainer.isShadowingModeEnabled {
                        HStack(spacing: 4) {
                            Circle().fill(UltimateDesignSystem.Colors.studioCrimson).frame(width: 6, height: 6)
                            Text("SHADOWING ACTIVE")
                                .font(UltimateDesignSystem.Typography.dialLabel)
                                .foregroundColor(UltimateDesignSystem.Colors.studioCrimson)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(UltimateDesignSystem.Colors.studioSurface)
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer()
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            fts5SearchSheetView
        }
    }
    
    // MARK: - Bilingual Subtitle Display with Word Tokens
    
    private func bilingualSubtitleBar(cue: SubtitleCue) -> some View {
        VStack(spacing: 6) {
            // Primary Language Words (Tappable for dictionary)
            let words = cue.primaryText.components(separatedBy: .whitespacesAndNewlines)
            WrappingHStack(words: words) { word in
                Button {
                    onPausePlayback()
                    lookupWordInDictionary(word)
                    UltimateHapticEngine.shared.playDetentSnap()
                } label: {
                    Text(word)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.40))
                        .cornerRadius(4)
                }
            }
            
            // Secondary Language Translation
            if !cue.secondaryText.isEmpty {
                Text(cue.secondaryText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.72))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(UltimateDesignSystem.Colors.studioBorder, lineWidth: 0.8)
        )
    }
    
    // MARK: - In-Video OCR Interactive Layer
    
    private var ocrBoundingBoxesLayer: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                
                ForEach(ocrItems) { item in
                    let rect = CGRect(
                        x: item.boundingBox.origin.x * geo.size.width,
                        y: item.boundingBox.origin.y * geo.size.height,
                        width: item.boundingBox.size.width * geo.size.width,
                        height: item.boundingBox.size.height * geo.size.height
                    )
                    
                    Button {
                        lookupWordInDictionary(item.text)
                        UltimateHapticEngine.shared.playDetentSnap()
                    } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(UltimateDesignSystem.Colors.neonTeal.opacity(0.20))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(UltimateDesignSystem.Colors.neonTeal, lineWidth: 1.5))
                            .frame(width: rect.width, height: rect.height)
                    }
                    .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }
    
    // MARK: - FTS5 Search Sheet
    
    private var fts5SearchSheetView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("SUBTITLE & MEMO FTS5 SEARCH")
                    .font(UltimateDesignSystem.Typography.dspTitle)
                    .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                Spacer()
                Button("Done") { showSearchSheet = false }
                    .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
            }
            .padding([.top, .horizontal], 16)
            
            // Search Input
            TextField("Search subtitles or section notes...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .onChange(of: searchQuery) { query in
                    searchResults = UltimateWaveformFTS5Database.shared.searchAnnotations(query: query)
                }
            
            // Search Results List
            List(searchResults) { result in
                Button {
                    onSeekToTime(result.startTime)
                    showSearchSheet = false
                    UltimateHapticEngine.shared.playDetentSnap()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(formatTime(result.startTime))
                                .font(UltimateDesignSystem.Typography.timecode)
                                .foregroundColor(UltimateDesignSystem.Colors.neonTeal)
                            Spacer()
                            if !result.title.isEmpty {
                                Text(result.title)
                                    .font(UltimateDesignSystem.Typography.dialLabel)
                                    .foregroundColor(UltimateDesignSystem.Colors.cyberOrange)
                            }
                        }
                        Text(result.content)
                            .font(.system(size: 14))
                            .foregroundColor(UltimateDesignSystem.Colors.textPrimary)
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(UltimateDesignSystem.Colors.obsidianBlack)
    }
    
    private func lookupWordInDictionary(_ word: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        UltimateBilingualSubtitleParser.showDictionary(for: word, from: rootVC)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// Helper Wrapping HStack for Word Tokens
private struct WrappingHStack<Content: View>: View {
    let words: [String]
    let content: (String) -> Content
    
    var body: some View {
        // Flow layout of words
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    content(word)
                }
            }
        }
    }
}
